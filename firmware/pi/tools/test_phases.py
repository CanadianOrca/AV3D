import numpy as np
import pytest

from av3d import config as C
from av3d import geometry as G
from av3d.phases import ON_BIT, PhaseSolver, check_in_limits, phase_fraction, to_steps

NO_FIX = dict(disabled={"bottom": set(), "top": set()}, calibration={"bottom": {}, "top": {}})


@pytest.fixture
def solver():
    return PhaseSolver(**NO_FIX)


def test_centre_point_gives_mirror_image_phases(solver):
    """Check 6: a bead at the centre gives mirror-image phases."""
    st = solver.steps((0, 0, 0), mode="focus")[0]          # (2, 144)
    grid = lambda b: np.array([[st[b, G.rowcol_to_channel(r, c) - 1] for c in range(12)]
                               for r in range(12)])
    bot, top = grid(0), grid(1)
    assert np.array_equal(bot, bot[::-1, :])               # mirror top-bottom
    assert np.array_equal(bot, bot[:, ::-1])               # mirror left-right
    assert np.array_equal(bot, bot.T)                      # square symmetry
    assert np.array_equal(bot, top)                        # both boards the same


def test_trap_mode_adds_half_cycle_to_top(solver):
    f = solver.steps((0.01, -0.005, 0.02), mode="focus")[0]
    t = solver.steps((0.01, -0.005, 0.02), mode="trap")[0]
    assert np.array_equal(t[0], f[0])
    assert np.array_equal(t[1], (f[1] + 16) % 32)


def test_phase_formula_by_hand():
    pos = np.array([[0.0, 0.0, 0.0]])
    lam = C.WAVELENGTH_M
    # a point exactly 1.25 wavelengths away: -1.25 mod 1 = 0.75 -> step 24
    assert to_steps(phase_fraction(pos, (0, 0, 1.25 * lam)))[0] == 24
    assert to_steps(phase_fraction(pos, (0, 0, 2.0 * lam)))[0] == 0


def test_waves_arrive_together(solver):
    """Delay + travel time should be the same for every transducer (mod a cycle)."""
    p = np.array([0.012, 0.007, -0.015])
    st = solver.steps(p, mode="focus")[0]
    d = np.linalg.norm(solver.positions - p, axis=-1)
    arrival = (st / 32 + d / C.WAVELENGTH_M) % 1.0          # in cycles, should be ~0
    error = np.angle(np.exp(2j * np.pi * arrival))         # wrapped to +/- pi
    assert np.max(np.abs(error)) <= 2 * np.pi * (0.5 / 32) + 1e-9   # within rounding


def test_channel_bytes_on_bit_and_disabled():
    s = PhaseSolver(disabled={"bottom": {5}, "top": {144}}, calibration={"bottom": {}, "top": {}})
    cb = s.channel_bytes([(0, 0, 0), (0.01, 0, 0)])
    assert cb.shape == (2, 2, 144) and cb.dtype == np.uint8
    assert cb[0, 0, 4] == 0 and cb[0, 1, 143] == 0
    mask = np.ones((2, 144), bool)
    mask[0, 4] = mask[1, 143] = False
    assert np.all(cb[:, mask] & ON_BIT)
    assert np.all((cb[:, mask] & 0x60) == 0)               # bits 6..5 always 0


def test_calibration_offsets():
    s = PhaseSolver(disabled={"bottom": set(), "top": set()},
                    calibration={"bottom": {1: 3}, "top": {}})
    base = PhaseSolver(**NO_FIX).steps((0, 0, 0))[0]
    assert s.steps((0, 0, 0))[0][0, 0] == (base[0, 0] + 3) % 32


def test_limits():
    check_in_limits((0.04, -0.04, 0.05))
    with pytest.raises(ValueError):
        check_in_limits((0.05, 0, 0))
    with pytest.raises(ValueError):
        check_in_limits((0, 0, -0.06))
