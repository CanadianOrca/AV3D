"""
Uploads shapes to both boards and controls the playback

Order rules, so boards are never out of step:
Play > bottom board first, then top
Stop > top board first, then bottom

Live moves such as catching and nudging the bead use two spare point slots
in turn: write the new position into the slot that is NOT playing, then SHOW it.
The FPGA swaps at every 40 khz cycle so there is never a half-written point.
"""

import time
import numpy as np

from . import config as C
from .import protocol as P
from .phases import PhaseSolver, check_in_limits
from .shapes import DEFAULT_COLOUR, path_length

class Player:
    def __init__(self, link, solver=None, boards=("bottom", "top"), mode="trap", sleep=time.sleep):
        self.link = link
        self.solver = solver or PhaseSolver()
        self.boards = tuple(boards)
        self.mode = mode
        self.sleep = sleep
        self.rate = C.DEFAULT_RATE
        self.count = 0
        self.shape = None
        self.shape_rgb = None
        self.position = np.zeros(3)
        self.colour = DEFAULT_COLOUR
        self.state = "off"
        self._live = 0

    # sending
    def _send(self, data, order=("bottom", "top")):
        for b in order:
            if b in self.boards:
                self.link.write(b, data)

    def _board_index(self, board):
        return 0 if board == "bottom" else 1

    def write_point(self, idx, point, rgb=None):
        rgb = self.colour if rgb is None else rgb
        cb = self.solver.channel_bytes(point, self.mode)[0] # 2, 144
        for b in self.boards:
            self.link.write(b, P.pack_write_point(idx, cb[self._board_index(b)], rgb))
    # shapes
    def upload(self, points, rgb=None):
        pts = np.atleast_2d(np.asarray(points, dtype=float))
        n = len(pts)
        if not 1 <= n <= C.MAX_SHAPE_POINTS:
            raise ValueError(f"a shape needs between 1 and {C.MAX_SHAPE_POINTS} points, got {n}")
        check_in_limits(pts)
        if rgb is None:
            rgb = np.tile(np.asarray(self.colour, dtype=np.uint8), (n, 1))
        rgb = np.asarray(rgb, dtype=np.uint8).reshape(n, 3)
        cb = self.solver.channel_bytes(pts, self.mode) # n, 2, 144
        for i in range(n):
            for b in self.boards:
                self.link.write(b, P.pack_write_point(i, cb[i, self._board_index(b)], rgb[i]))
        self._send(P.pack_set_count(n))
        self.count, self.shape, self.shape_rgb = n, pts, rgb

    def set_rate(self, cycles_per_point):
        self.rate = int(min(max(cycles_per_point, C.MIN_RATE), C.MAX_RATE))
        self._send(P.pack_set_rate(self.rate), order=("top", "bottom"))
        return self.rate

    def points_per_second(self):
        return C.FREQ_HZ / self.rate

    def loop_time(self):
        return self.count * self.rate / C.FREQ_HZ if self.count else 0.0

    def rate_for_loop_time(self, seconds):
        return max(C.MIN_RATE, int(round(seconds * C.FREQ_HZ / max(self.count, 1))))

    def bead_speed(self, rate=None):
        if self.shape is None or self.count < 2:
            return 0.0
        rate = self.rate if rate is None else rate
        return path_length(self.shape) * (C.FREQ_HZ / rate) / self.count

    def min_rate(self, max_speed=C.MAX_SPEED_M_S):
        if self.shape is None or self.count < 2:
            return C.MIN_RATE
        need = path_length(self.shape) * C.FREQ_HZ / (self.count * max_speed)
        return int(min(max(np.ceil(need), C.MIN_RATE), C.MAX_RATE))

    def safe_rate_for_loop_time(self, seconds):
        return max(self.rate_for_loop_time(seconds), self.min_rate())

    # playback
    def play(self):
        self._send(P.pack_play(), order=("bottom", "top"))
        self.state = "playing"

    def stop(self):
        self._send(P.pack_stop(), order=("top", "bottom"))
        self.state = "stopped"
        if self.shape is not None:
            board = "top" if "top" in self.boards else self.boards[0]
            idx = self.index(board)
            if 0 <= idx < self.count:
                self.position = self.shape[idx].copy()

    def off(self):
        self._send(P.pack_off())
        self.state = "off"

    # live control
    def hold(self, pos, rgb=None):
        pos = np.asarray(pos, dtype=float)
        check_in_limits(pos)
        slot = C.LIVE_SLOTS[self._live]
        self._live ^= 1
        self.write_point(slot, pos, rgb)
        self._send(P.pack_show(slot))
        self.position = pos.copy()
        self.state = "holding"

    def home(self):
        self.hold((0.0, 0.0, 0.0))

    def nudge(self, dx=0.0, dy=0.0, dz=0.0):
        target = self.position + np.array([dx, dy, dz])
        target[:2] = np.clip(target[:2], -C.LIMIT_XY_M, C.LIMIT_XY_M)
        target[2] = np.clip(target[2], -C.LIMIT_Z_M, C.LIMIT_Z_M)
        self.move_to(target)

    def move_to(self, target, speed=0.02, update_hz=100):
        target = np.asarray(target, dtype=float)
        check_in_limits(target)
        start = self.position
        dist = float(np.linalg.norm(target - start))
        steps = max(1, int(np.ceil(dist / (speed / update_hz))))
        for k in range(1, steps + 1):
            self.hold(start + (target - start) * k / steps)
            if k < steps:
                self.sleep(1.0 / update_hz)

    def start_shape(self, points, rgb=None, loop_time=0.10, ram_s=3.0):
        pts = np.atleast_2d(np.asarray(points, dtype=float))
        self.move_to(pts[0])
        self.upload(pts, rgb)
        target = self.safe_rate_for_loop_time(loop_time)
        start = min(C.MAX_RATE, target * 10)
        self.set_rate(start)
        self.play()
        steps = 15
        for k in range(1, steps + 1):
            self.sleep(ram_s / steps)
            self.set_rate(int(round(start + (target - start) * k / steps)))
        return target

    # diagnostics
    def status(self):
        return {b: P.parse_status(self.link.transfer(b, P.pack_nop(b"\x00"))[0]) for b in self.boards}

    def index(self, board="top"):
        reply = self.link.transfer(board, P.pack_get_index())
        return (reply[1] << 8) | reply[2]

    def echo_test(self, board, n=64, seed=None):
        rng = np.random.default_rng(seed)
        payload = bytes(rng.integers(0, 256, n, dtype=np.uint8))
        sent = P.pack_nop(payload)
        reply = self.link.transfer(board, sent)
        status = P.parse_status(reply[0])
        bad = [i for i in range(1, len(sent)) if reply[i] != sent[i - 1]]
        return status, bad

    def test_pattern(self, mode):
        self._send(P.pack_test(mode))
        self.state = "test" if mode else "off"

    def set_trim(self, ticks):
        if "bottom" in self.boards:
            self.link.write("bottom", P.pack_set_trim(ticks))
