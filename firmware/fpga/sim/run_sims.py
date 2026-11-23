#!/usr/bin/env python3
"""Runs every AV3D test (made by Claude, test use only).

    python run_sims.py              everything: FPGA testbenches, Pi->FPGA vectors, Pi unit tests,
                                    sound simulation
    python run_sims.py --quick      skip the slow ones (button, two-board system, 120-point vectors)
    python run_sims.py --wave       also write .vcd waveforms into sim/build (open with GTKWave)
    python run_sims.py --fpga-only  only the Verilog testbenches (no Pi tests, no sound simulation)
    python run_sims.py board        only tests whose name contains "board"
    python run_sims.py -j 2         run at most 2 tests at the same time (default: one per CPU core)

Needs Icarus Verilog 11 or newer (iverilog and vvp on PATH). The Pi tests need numpy and pytest,
the sound simulation needs scipy (pip install -r ../../pi/requirements-dev.txt). A test whose
Python package is missing is shown as SKIPPED.

Every test prints PASS/FAIL lines; the full output of each one is saved in sim/build/<test>.log.
Exit status is 0 only if nothing failed.
"""

import argparse
import concurrent.futures as cf
import glob
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FPGA = os.path.dirname(HERE)
PI = os.path.join(os.path.dirname(FPGA), "pi")
BUILD = os.path.join(HERE, "build")

# name, testbench module, testbench files, extra iverilog arguments, time limit (s), slow
FPGA_TESTS = [
    ("channel_gen: phase rule, on bit, test modes", "tb_channel_gen", ["tb_channel_gen.v"], [], 300, False),
    ("shift_out: 18 shift registers, bit order, /OE", "tb_shift_out", ["tb_shift_out.v", "hc595.v"], [], 300, False),
    ("cycle_timer: 40 kHz cycle, SYNC lock, +-200 ppm", "tb_cycle_timer", ["tb_cycle_timer.v"], [], 600, False),
    ("spi_slave: 4 MHz writes, 1 MHz reads, GET_INDEX", "tb_spi_slave", ["tb_spi_slave.v"], [], 300, False),
    ("cmd_decoder: every command and its limits", "tb_cmd_decoder", ["tb_cmd_decoder.v"], [], 300, False),
    ("led_pwm: duty cycle and LED test pattern", "tb_led_pwm", ["tb_led_pwm.v"], [], 300, False),
    ("board: player, rate, STEP pulses, live slots", "tb_board", ["tb_board.v", "hc595.v"], [], 1200, False),
    ("button S1: real 9.7 ms debounce", "tb_button", ["tb_button.v"], [], 1800, True),
    ("system: two boards, bottom crystal +200 ppm", "tb_system", ["tb_system.v", "hc595.v"],
     ["-Ptb_system.PPM=200.0"], 3600, True),
    ("system: two boards, bottom crystal -200 ppm", "tb_system", ["tb_system.v", "hc595.v"],
     ["-Ptb_system.PPM=-200.0"], 3600, True),
]

# name, vector folder (inside sim), make_vectors.py arguments, time limit (s), slow
VECTOR_TESTS = [
    ("Pi->FPGA vectors: 12 points, rate 2", "vectors_2b", ["--n", "12", "--rate", "2"], 1200, False),
    ("Pi->FPGA vectors: 120 points, rate 1", "vectors", ["--n", "120", "--rate", "1"], 3600, True),
]


def find_tool(name):
    path = shutil.which(name)
    if path:
        return path
    for guess in (r"C:\iverilog\bin", r"C:\Program Files\iverilog\bin",
                  r"C:\Program Files (x86)\iverilog\bin", r"C:\oss-cad-suite\bin"):
        p = os.path.join(guess, name + ".exe")
        if os.path.exists(p):
            return p
    return None


def has_modules(*names):
    return [n for n in names if importlib.util.find_spec(n) is None]


def safe_name(name):
    return re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_")[:50]


# one unique file name per test: number + short name (the two system tests differ only in
# "+" / "-", which a plain name would lose)
TAGS = {t[0]: f"{i:02d}_{safe_name(t[0])}" for i, t in enumerate(FPGA_TESTS + VECTOR_TESTS)}


def run(cmd, cwd, limit):
    """Runs a command, returns (exit code or None on timeout, output text)."""
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=limit,
                           errors="replace")
        return r.returncode, r.stdout + r.stderr
    except subprocess.TimeoutExpired as e:
        out = e.stdout or ""
        if isinstance(out, bytes):
            out = out.decode(errors="replace")
        return None, out + f"\nTIMEOUT after {limit} s"


class Result:
    def __init__(self, name, status, lines, passed=0, failed=0, secs=0.0, note=""):
        self.name, self.status, self.lines = name, status, lines
        self.passed, self.failed, self.secs, self.note = passed, failed, secs, note
        self.exit_after_pass = None     # simulator exit code if it failed only after finishing


def exit_text(code):
    """Exit status as text; Windows crash codes are easier to read in hex."""
    if code is None:
        return "timed out"
    if code < 0 or code > 255:
        return f"exit code {code} (0x{code & 0xFFFFFFFF:08X})"
    return f"exit code {code}"


def verilog_result(name, code, out, secs, log_path):
    lines = [l for l in out.splitlines()
             if l.startswith(("PASS", "FAIL", "INFO", "ERROR", "WARNING")) or "TIMEOUT" in l]
    n_pass = sum(1 for l in lines if l.startswith("PASS"))
    n_fail = sum(1 for l in lines if l.startswith("FAIL"))
    finished = "SUMMARY failures=0" in out
    ok = finished and n_fail == 0 and n_pass > 0
    log = os.path.relpath(log_path, os.path.dirname(HERE))
    late_exit = None
    if ok:
        note = ""
        if code not in (0, None):
            # every check ran and the results file was closed; the simulator itself then
            # failed while shutting down (reported once at the end, not per test)
            late_exit = code
    elif code is None:
        note = f"timed out, see {log}"
    elif "SUMMARY" not in out:
        note = (f"no results came back from the simulator ({exit_text(code)}); "
                f"its screen output is in {log}")
    else:
        note = f"see {log}"
    r = Result(name, "PASS" if ok else "FAIL", lines, n_pass, n_fail, secs, note)
    r.exit_after_pass = late_exit
    return r


def run_to_file(cmd, cwd, limit, log_path):
    """Runs a command with its screen output going straight into a file (not a pipe)."""
    with open(log_path, "w", encoding="utf-8", errors="replace") as log:
        try:
            r = subprocess.run(cmd, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                               stdin=subprocess.DEVNULL, timeout=limit)
            return r.returncode
        except subprocess.TimeoutExpired:
            return None


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def compile_and_sim(name, top, tb_files, extra, limit, args, src, iverilog, vvp, plusargs=(),
                    incdirs=()):
    t0 = time.time()
    tag = TAGS[name]
    exe = os.path.join(BUILD, tag + ".vvp")
    log_path = os.path.join(BUILD, tag + ".log")
    rep_name = tag + "_results.txt"
    rep_path = os.path.join(BUILD, rep_name)
    for p in (exe, log_path, rep_path):
        if os.path.exists(p):
            os.remove(p)
    cmd = [iverilog, "-g2012", "-DSIMULATION", "-s", top, "-o", exe, "-I" + HERE] + list(extra)
    cmd += ["-I" + d for d in incdirs]
    if args.wave:
        cmd.append("-DDUMP")
    cmd += [os.path.join(HERE, f) for f in tb_files] + src
    code, out = run(cmd, HERE, 300)
    if code != 0 or not os.path.exists(exe):
        return Result(name, "FAIL", out.strip().splitlines()[-15:], note="did not compile")
    # the report path is relative to sim/ (vvp runs there), which avoids spaces and
    # backslashes in plusargs on Windows
    code = run_to_file([vvp, "-n", exe, "+report=build/" + rep_name] + list(plusargs), HERE,
                       limit, log_path)
    screen = read_text(log_path)
    report = read_text(rep_path)
    # the report file is written by the testbench itself and closed before $finish, so it
    # is used when present; the screen output is the fallback
    text = report if "SUMMARY" in report else screen
    return verilog_result(name, code, text, time.time() - t0, log_path)


def fpga_job(test, args, src, iverilog, vvp):
    name, top, files, extra, limit, _slow = test
    return compile_and_sim(name, top, files, extra, limit, args, src, iverilog, vvp)


def vector_job(test, args, src, iverilog, vvp):
    name, folder, mv_args, limit, _slow = test
    missing = has_modules("numpy")
    if missing:
        return Result(name, "SKIPPED", [], note="needs numpy (pip install numpy)")
    t0 = time.time()
    make = os.path.join(PI, "tools", "make_vectors.py")
    code, out = run([sys.executable, make, "--out", os.path.join(HERE, folder)] + mv_args, PI, 300)
    if code != 0:
        tail = out.strip().splitlines()[-6:]
        return Result(name, "FAIL", ["make_vectors.py (the Pi code) failed:"] + tail,
                      secs=time.time() - t0, note="Pi code error, see above")
    r = compile_and_sim(name, "tb_vectors", ["tb_vectors.v", "hc595.v"], [], limit, args, src,
                        iverilog, vvp, plusargs=["+vec=" + folder],
                        incdirs=[os.path.join(HERE, folder)])
    r.secs = time.time() - t0
    return r


def pytest_job(args):
    name = "Pi unit tests (firmware/pi/tools/test_*.py)"
    missing = has_modules("pytest", "numpy")
    if missing:
        return Result(name, "SKIPPED", [], note="needs " + ", ".join(missing) +
                      " (pip install -r firmware/pi/requirements.txt)")
    t0 = time.time()
    code, out = run([sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", "tools"],
                    PI, 900)
    with open(os.path.join(BUILD, "pi_unit_tests.log"), "w", encoding="utf-8") as f:
        f.write(out)
    passed = int(m.group(1)) if (m := re.search(r"(\d+) passed", out)) else 0
    failed = int(m.group(1)) if (m := re.search(r"(\d+) failed", out)) else 0
    failed += int(m.group(1)) if (m := re.search(r"(\d+) errors?", out)) else 0
    lines = [l for l in out.splitlines() if l.startswith(("FAILED", "ERROR"))]
    lines = ["FAIL " + l for l in lines]
    ok = code == 0 and failed == 0 and passed > 0
    return Result(name, "PASS" if ok else "FAIL", lines, passed, failed, time.time() - t0,
                  "" if ok else "full output in sim/build/pi_unit_tests.log")


def sound_job(args):
    name = "sound simulation (firmware/pi/tools/sound_sim.py)"
    missing = has_modules("numpy", "scipy")
    if missing:
        return Result(name, "SKIPPED", [], note="needs " + ", ".join(missing) +
                      " (pip install -r firmware/pi/requirements-dev.txt)")
    t0 = time.time()
    code, out = run([sys.executable, os.path.join("tools", "sound_sim.py")], PI, 900)
    with open(os.path.join(BUILD, "sound_sim.log"), "w", encoding="utf-8") as f:
        f.write(out)
    lines = out.strip().splitlines()
    ok = code == 0 and "CHECK 3: PASS" in out
    n_pass = sum(1 for l in lines if l.rstrip().endswith("PASS") and "CHECK" not in l)
    n_fail = sum(1 for l in lines if l.rstrip().endswith("FAIL") and "CHECK" not in l)
    shown = [("FAIL " if not ok else "INFO ") + l for l in lines[-12:]]
    return Result(name, "PASS" if ok else "FAIL", shown, n_pass, n_fail, time.time() - t0)


def main():
    ap = argparse.ArgumentParser(description="Run every AV3D test.")
    ap.add_argument("only", nargs="?", default="", help="run only tests whose name contains this text")
    ap.add_argument("--quick", action="store_true", help="skip the slow tests")
    ap.add_argument("--wave", action="store_true", help="dump .vcd waveforms into sim/build")
    ap.add_argument("--fpga-only", action="store_true", help="only the Verilog testbenches")
    ap.add_argument("--src", default=os.path.join(FPGA, "src"), help="folder with the firmware .v files")
    ap.add_argument("-j", "--jobs", type=int, default=os.cpu_count() or 1, help="tests run at once")
    args = ap.parse_args()

    iverilog, vvp = find_tool("iverilog"), find_tool("vvp")
    if not iverilog or not vvp:
        sys.exit("cannot find iverilog/vvp: install Icarus Verilog and put its bin folder on PATH")
    src = sorted(glob.glob(os.path.join(args.src, "*.v")))
    if not src:
        sys.exit(f"no .v files in {args.src}")
    os.makedirs(BUILD, exist_ok=True)
    for old in glob.glob(os.path.join(BUILD, "*")):
        if old.endswith((".vvp", ".log", "_results.txt")):
            try:
                os.remove(old)
            except OSError:
                pass

    def wanted(name, slow):
        return (args.only.lower() in name.lower()) and not (args.quick and slow)

    jobs = []
    for t in FPGA_TESTS:
        if wanted(t[0], t[5]):
            jobs.append((fpga_job, (t, args, src, iverilog, vvp)))
    for t in VECTOR_TESTS:
        if wanted(t[0], t[4]) and not args.fpga_only:
            jobs.append((vector_job, (t, args, src, iverilog, vvp)))
    if not args.fpga_only and wanted("Pi unit tests", False):
        jobs.append((pytest_job, (args,)))
    if not args.fpga_only and wanted("sound simulation", False):
        jobs.append((sound_job, (args,)))
    if not jobs:
        sys.exit("no test matches")

    print(f"Running {len(jobs)} tests, {max(1, args.jobs)} at a time "
          f"(firmware from {os.path.relpath(args.src, HERE)})", flush=True)
    t_start = time.time()
    results = []
    with cf.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = {pool.submit(fn, *a): a for fn, a in jobs}
        for fut in cf.as_completed(futures):
            r = fut.result()
            results.append(r)
            print(f"\n=== {r.name}: {r.status}" + (f" ({r.secs:.0f} s)" if r.secs else ""), flush=True)
            for line in r.lines:
                print("  " + line)
            if r.note:
                print("  -> " + r.note)

    order = [j[1][0][0] if j[0] in (fpga_job, vector_job) else None for j in jobs]
    results.sort(key=lambda r: order.index(r.name) if r.name in order else len(order))
    print("\n" + "-" * 78)
    for r in results:
        counts = f"{r.passed} passed, {r.failed} failed" if r.status != "SKIPPED" else r.note
        print(f"{r.status:8s} {r.name:52s} {counts}")
    print("-" * 78)
    late = [r for r in results if r.exit_after_pass is not None]
    if late:
        codes = ", ".join(sorted({exit_text(r.exit_after_pass) for r in late}))
        print(f"Note: the simulator (vvp) ended with {codes} after {len(late)} of the tests had")
        print("      finished. Every check had already run and its results were saved, so the")
        print("      results above are complete. 0xC0000005 is a crash inside the simulator while")
        print("      it shuts down (seen with Icarus 14.0-devel on Windows), not a problem in AV3D.")
    bad = [r for r in results if r.status == "FAIL"]
    skipped = [r for r in results if r.status == "SKIPPED"]
    total = time.time() - t_start
    if bad:
        print(f"{len(bad)} TEST(S) FAILED  ({total:.0f} s)")
    elif skipped:
        print(f"ALL TESTS THAT RAN PASSED, {len(skipped)} SKIPPED  ({total:.0f} s)")
    else:
        print(f"ALL TESTS PASSED  ({total:.0f} s)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
