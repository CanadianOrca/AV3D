#!/usr/bin/env python3
"""Check 5: SPI echo test against a real Tang Nano (run on the Pi).

Wire the Pi to the board (or straight to a bare Tang Nano loaded with the
firmware), then:

    python3 tools/spi_echo_test.py              # both boards, 200 rounds each
    python3 tools/spi_echo_test.py --boards top --rounds 1000

It reads the STATUS byte (checks the magic bits and that the board on each
chip-select knows whether it is TOP or BOTTOM), then sends random bytes and
checks each one comes back one byte later. Pass = every byte echoed.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from av3d.player import Player         # noqa: E402
from av3d.protocol import SpiLink      # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--boards", choices=["both", "top", "bottom"], default="both")
    ap.add_argument("--rounds", type=int, default=200)
    ap.add_argument("--len", type=int, default=64, help="bytes per round")
    a = ap.parse_args()
    boards = ("bottom", "top") if a.boards == "both" else (a.boards,)

    link = SpiLink()
    player = Player(link, boards=boards)
    ok = True
    for b in boards:
        bad_total = 0
        status = None
        for r in range(a.rounds):
            status, bad = player.echo_test(b, a.len, seed=r)
            bad_total += len(bad)
        role_ok = status.valid and status.is_top == (b == "top")
        print(f"{b:6s}: {status}")
        print(f"        echo errors: {bad_total} of {a.rounds * a.len} bytes"
              f"{'' if role_ok else '   <-- wrong board on this chip-select (J7/J8)'}")
        ok &= status.valid and role_ok and bad_total == 0
    link.close()
    print("CHECK 5 (SPI):", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
