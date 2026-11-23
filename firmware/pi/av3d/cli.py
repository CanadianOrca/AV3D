"""
Keyboard Control

python3 av3d.cli real board on pi
python3 av3d.cli --pretend -v no hardware, prints the bytes (computer)
python3 av3d.cli --focus --boards top one board, plain focus

Catching the bead: press h (trap holds in centre), put the bead in slowly with tweezers
nudge it gently then pick a shape. The shape starts slowly from where the bead is and
speeds up.

"""

import argparse
import sys

from av3d import config as C
from av3d import shapes
from av3d.player import Player
from av3d.protocol import PretendLink, SpiLink

HELP = """
 keys
   h        home: hold the trap still in the centre
   a / d    x - / +        w / s    y + / -        r / f    z + / -
   [ / ]    smaller / bigger nudge step
   1..9     shapes: 1 circle 2 square 3 triangle 4 star 5 figure-8
                    6 lissajous 7 spiral 8 cube 9 text (asks for words)
   p        pause / resume the shape (pause holds the bead where it is)
   + / -    faster / slower
   c        next colour
   t        test pattern 1 -> 2 -> 3 -> off (no Pi maths, just the FPGA)
   i        board status and sync check
   o        everything off
   ?        this help          q   quit (turns everything off)
"""

COLOURS = [(180, 180, 180), (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 160, 0), (0, 200, 255), (255, 0, 200), (0, 0, 0)]
SHAPE_KEYS = {"1": "circle", "2": "square", "3": "triangle", "4": "star", "5": "figure8", "6": "lissajous", "7": "spiral", "8": "cube", "9": "text"}

CREDITS = """
    ============ AV3D ============
    made by
    Jason Cui - Primary Lead, Firmware
    Andre Au - Secondary Lead, CAD Design
    Harish Maharaja - PCB Design, Electronics
    Lucas Huang - Planning, Administration

    with thanks to
    Fallen @ Hack Club for making the project possible
    vdatp @ Danfoisy for inspiring our team
    ==============================
"""

def show_credits():
    print(CREDITS)

# single keys
def make_getkey():
    try:
        import msvcrt # windows

        def getkey():
            ch = msvcrt.getwch()
            if ch in ("\x00", "\xe0"): # arrow or function key prefix
                msvcrt.getwch()
                return ""
            return ch
        return getkey
    except ImportError:
        import termios
        import tty

        def getkey(): # Linux / macOS / Pi over SSH
            fd = sys.stdin.fileno()
            old = termios.tcgetattr(fd)
            try:
                tty.setraw(fd)
                return sys.stdin.read(1)
            finally:
                termios.tcsetattr(fd, termios.TCSADRAIN, old)
        return getkey

def fmt_mm(p):
    return "(" + ", ".join(f"{v * 1000:+.1f}" for v in p) + ") mm"

def main(argv=None):
    ap = argparse.ArgumentParser(description="AV3D keyboard control")
    ap.add_argument("--pretend", action="store_true", help="no hardware, print bytes")
    ap.add_argument("-v", "--verbose", action="store_true", help="show every transaction")
    ap.add_argument("--boards", choices=["both", "top", "bottom"], default="both")
    ap.add_argument("--focus", action="store_true",
                    help="plain focus instead of a trap (bring-up with one board)")
    ap.add_argument("--loop", type=float, default=0.10, help="shape loop time in seconds")
    ap.add_argument("--credits", action="store_true", help=argparse.SUPPRESS)
    args = ap.parse_args(argv)
    show_credits()
    if args.credits:
        return

    boards = ("bottom", "top") if args.boards == "both" else (args.boards,)
    if args.pretend:
        link = PretendLink(verbose=args.verbose)
    else:
        link = SpiLink()
    player = Player(link, boards=boards, mode="focus" if args.focus else "trap")

    print("AV3D - press ? for help, q to quit")
    for b, st in player.status().items():
        print(f"  {b}: {st}")
        if st.valid and st.is_top != (b == "top"):
            print(f"  WARNING: the board on the {b} chip-select says it is the "
                  f"{'top' if st.is_top else 'bottom'} board. Check the J7 and J8 shunts.")

    getkey = make_getkey()
    step = 0.5e-3
    colour_i = 0
    test_mode = 0
    loop_time = args.loop

    try:
        while True:
            key = getkey()
            if key in ("q", "\x03"): # q or Ctrl-C
                break
            elif key == "?":
                print(HELP)
            elif key == "h":
                if player.state == "holding":
                    player.move_to((0.0, 0.0, 0.0)) # glide back, do not jump
                else:
                    player.home()
                print("holding at the centre")
            elif key and key in "adwsrf":
                if player.state == "playing":
                    print("pause first (p)")
                    continue
                d = {"a": (-step, 0, 0), "d": (step, 0, 0), "w": (0, step, 0),
                     "s": (0, -step, 0), "r": (0, 0, step), "f": (0, 0, -step)}[key]
                player.nudge(*d)
                print(f"bead at {fmt_mm(player.position)}")
            elif key == "[":
                step = max(step / 2, 0.125e-3)
                print(f"nudge step {step * 1000:.3f} mm")
            elif key == "]":
                step = min(step * 2, 4e-3)
                print(f"nudge step {step * 1000:.3f} mm")
            elif key in SHAPE_KEYS:
                name = SHAPE_KEYS[key]
                kwargs = {}
                if name == "text":
                    print("text (A-Z 0-9 - + . ! ? *): ", end="", flush=True)
                    kwargs["string"] = input().strip() or "AV3D"
                try:
                    pts, rgb = shapes.make(name, colour=COLOURS[colour_i], **kwargs)
                except ValueError as e:
                    print(e)
                    continue
                print(f"{name}: {len(pts)} points, gliding to the start ...")
                rate = player.start_shape(pts, rgb, loop_time=loop_time)
                capped = " (slowed to the speed limit)" if rate > player.rate_for_loop_time(loop_time) else ""
                print(f"playing at {C.FREQ_HZ / rate:.0f} points/s, "
                      f"loop {player.loop_time() * 1000:.0f} ms, "
                      f"bead speed {player.bead_speed():.2f} m/s{capped}")
            elif key == "p":
                if player.state == "playing":
                    player.stop()
                    player.hold(player.position)
                    print(f"paused, holding at {fmt_mm(player.position)}")
                elif player.shape is not None:
                    player.start_shape(player.shape, player.shape_rgb, loop_time=loop_time)
                    print("playing")
            elif key in ("+", "="):
                if player.count:
                    loop_time = max(loop_time / 1.25, 0.02)
                    rate = player.safe_rate_for_loop_time(loop_time)
                    if rate > player.rate_for_loop_time(loop_time):
                        loop_time = player.count * rate / C.FREQ_HZ
                        print(f"speed limit {C.MAX_SPEED_M_S} m/s reached "
                              f"(raise MAX_SPEED_M_S in config.py once the bead holds well)")
                    player.set_rate(rate)
                    print(f"loop {player.loop_time() * 1000:.0f} ms, "
                          f"speed {player.bead_speed():.2f} m/s")
            elif key == "-":
                if player.count:
                    loop_time = min(loop_time * 1.25, 5.0)
                    player.set_rate(player.safe_rate_for_loop_time(loop_time))
                    print(f"loop {player.loop_time() * 1000:.0f} ms, "
                          f"speed {player.bead_speed():.2f} m/s")
            elif key == "c":
                colour_i = (colour_i + 1) % len(COLOURS)
                player.colour = COLOURS[colour_i]
                print(f"colour {COLOURS[colour_i]} (used for the next hold or shape)")
                if player.state == "holding":
                    player.hold(player.position)
            elif key == "t":
                test_mode = (test_mode + 1) % 4
                player.test_pattern(test_mode)
                print(f"test pattern {test_mode}" if test_mode else "test pattern off")
            elif key == "i":
                for b, st in player.status().items():
                    print(f"  {b}: {st}")
                if len(boards) == 2:
                    print(f"  point index: bottom {player.index('bottom')}, "
                          f"top {player.index('top')}")
            elif key == "*":
                show_credits()
                pts, rgb = shapes.make("text", string="*", colour=(255, 0, 80))
                player.start_shape(pts, rgb, loop_time=loop_time)
                print("<3")
            elif key == "o":
                player.off()
                print("all off")

    finally:
        player.off()
        link.close()
        print("off. bye")

if __name__ == "__main__":
    main()
