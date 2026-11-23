"""
the physics bead positions > phase step of transducer

for a focus at point P, each transducer is delayed so that all waves arrive at P in the same moment.
A transducer at distance d need its wave to start d/c earlier than the one at distance 0
which is (-d / wavelength) mod 1. The FPGA phase p delays a channel by p/32 of a cycle,
so p = round(32 * ((-d / wavelength) mod 1)) mod 32

both boards focus on p and the top board gets an extra half cycle.
the two waves cancel at p and squeeze the bead into it
channel byte sent to fpga: 0x80 for a working channel, 0x00 for a off
"""

import numpy as np

from . import config as C
from . import geometry

ON_BIT = 0x80

def phase_fraction(positions, point, wavelength=C.WAVELENGTH_M):
    d = np.linalg.norm(np.asarray(positions) - np.asarray(point), axis=-1)
    return np.mod(-d / wavelength, 1.0)

def to_steps(fraction, steps=C.PHASE_STEPS):
    return np.mod(np.rint(np.asarray(fraction) * steps).astype(int), steps)

class PhaseSolver:

    def __init__(self, gap=C.BOARD_GAP_M, wavelength=C.WAVELENGTH_M,
                 flip=C.TOP_FLIP_AXIS, disabled=None, calibration=None):
        self.positions = geometry.all_positions(gap=gap, flip=flip)
        self.wavelength = wavelength
        disabled = C.DISABLED_CHANNELS if disabled is None else disabled
        calibration = C.load_calibration() if calibration is None else calibration
        self.enabled = np.ones((2, C.CHANNELS_PER_BOARD), dtype=bool)
        self.cal = np.zeros((2, C.CHANNELS_PER_BOARD), dtype=int)
        for b, name in enumerate(geometry.BOARDS):
            for ch in disabled.get(name, ()):
                self.enabled[b, ch - 1] = False
            for ch, steps in calibration.get(name, {}).items():
                self.cal[b, ch - 1] = steps

    def steps(self, points, mode="trap"):
        pts = np.atleast_2d(np.asarray(points, dtype=float))
        d = np.linalg.norm(self.positions[None, :, :, :] - pts[:, None, None, :], axis=-1)
        st = to_steps(np.mod(-d / self.wavelength, 1.0))
        if mode == "trap":
            st[:, 1, :] += C.TRAP_OFFSET_STEPS
        elif mode != "focus":
            raise ValueError("mode must be in trap or focus")
        st = st + self.cal[None, :, :]
        return np.mod(st, C.PHASE_STEPS)

    def channel_bytes(self, points, mode="trap"):
        st = self.steps(points, mode)
        out = (st | ON_BIT).astype(np.uint8)
        out[:, ~self.enabled] = 0
        return out

def check_in_limits(points):
    pts = np.atleast_2d(np.asarray(points, dtype=float))
    bad = (np.abs(pts[:, 0]) > C.LIMIT_XY_M + 1e-12) | \
          (np.abs(pts[:, 1]) > C.LIMIT_XY_M + 1e-12) | \
          (np.abs(pts[:, 2]) > C.LIMIT_Z_M + 1e-12)
    if bad.any():
        i = int(np.argmax(bad))
        raise ValueError(f"Point {i} {pts[i]} is out of limits "
                         f"(|x|,|y| <= {C.LIMIT_XY_M} m, |z| <= {C.LIMIT_Z_M} m)")
