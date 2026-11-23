#!/usr/bin/env python3
"""Check 4 helper: make the byte files the FPGA testbenches play back.

The bytes come from the REAL Pi code (PhaseSolver + protocol), so the
simulation proves the Python side and the Verilog side agree byte for byte.

Writes into firmware/fpga/sim/vectors/:
    bottom_stream.hex, top_stream.hex   SPI traffic, one value per line:
                                        00..FF = a byte, 100 = CS goes high
                                        (end of a transaction), 1FF = end
    expected.hex                        the channel bytes for every point:
                                        point 0 bottom (144), point 0 top (144),
                                        point 1 bottom ...
    params.vh                           N_POINTS and RATE for the testbenches

    python tools/make_vectors.py                # 120 random points (tb_top)
    python tools/make_vectors.py --n 12 --rate 2 --out ../fpga/sim/vectors_2b
"""

import argparse
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from av3d import config as C           # noqa: E402
from av3d import protocol as P         # noqa: E402
from av3d.phases import PhaseSolver    # noqa: E402

DEFAULT_OUT = Path(__file__).resolve().parents[2] / "fpga" / "sim" / "vectors"


def make(n=120, rate=1, seed=42, out=DEFAULT_OUT):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)
    pts = np.column_stack([rng.uniform(-0.03, 0.03, n), rng.uniform(-0.03, 0.03, n),
                           rng.uniform(-0.03, 0.03, n)])
    pts[0] = (0.0, 0.0, 0.0)                               # always include the centre
    rgb = rng.integers(0, 256, (n, 3), dtype=np.uint8)
    # one dead channel per board, to test the "off" bit end to end
    solver = PhaseSolver(disabled={"bottom": {17}, "top": {100}},
                         calibration={"bottom": {}, "top": {}})
    cb = solver.channel_bytes(pts, mode="trap")            # (n, 2, 144)

    for b, name in enumerate(("bottom", "top")):
        lines = []
        for i in range(n):
            lines += [f"{x:03x}" for x in P.pack_write_point(i, cb[i, b], rgb[i])] + ["100"]
        for cmd in (P.pack_set_count(n), P.pack_set_rate(rate), P.pack_play()):
            lines += [f"{x:03x}" for x in cmd] + ["100"]
        lines.append("1ff")
        (out / f"{name}_stream.hex").write_text("\n".join(lines) + "\n")

    exp = [f"{x:02x}" for x in cb.reshape(-1)]
    (out / "expected.hex").write_text("\n".join(exp) + "\n")
    (out / "params.vh").write_text(f"`define N_POINTS {n}\n`define RATE {rate}\n"
                                   f"`define STREAM_LEN {len(lines)}\n")
    print(f"wrote {n} points (rate {rate}) to {out}")
    return pts, cb


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=120)
    ap.add_argument("--rate", type=int, default=1)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    a = ap.parse_args()
    make(a.n, a.rate, a.seed, a.out)
