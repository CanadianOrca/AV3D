#!/usr/bin/env python3
"""Check 3: sound simulation of all 288 transducers, using OUR phase code.

For each test point it:
  1. asks av3d.phases for the real phase steps (so the 32-step rounding is in),
  2. adds a random error of up to +/-10 degrees per transducer,
  3. adds up the sound from every transducer (piston model, far field),
  4. works out the Gor'kov potential U for a small foam bead, and
  5. checks that U has a minimum (a trap) within 1.5 mm of the point, that it
     pushes back in x, y and z, and that the upward push beats the bead's weight.

Pass rule from the plan: a trap at the centre and at points 30 mm off-centre.

    python tools/sound_sim.py              # all test points
    python tools/sound_sim.py --plot       # also saves sound_field.png (matplotlib)
    python tools/sound_sim.py --p0 1.0     # weaker transducers (Pa*m at 1 m)

P0 (pressure amplitude 1 m in front of one transducer at our 24 V drive) is
the big unknown. 2.0 Pa*m is a cautious guess for a 10 mm 40 kHz unit; check
the Manorshi datasheet's sound pressure level and rerun.
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from scipy.special import j1

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from av3d import config as C           # noqa: E402
from av3d import geometry              # noqa: E402
from av3d.phases import PhaseSolver    # noqa: E402

RHO_AIR = 1.2                          # kg/m^3
RHO_BEAD = 25.0                        # expanded polystyrene, kg/m^3
BEAD_D = 1.5e-3                        # m
PISTON_R = 4.5e-3                      # radiating radius of a 10 mm transducer

TEST_POINTS_MM = [(0, 0, 0), (30, 0, 0), (0, 30, 0), (-30, 0, 0), (21, 21, 0),
                  (0, 0, 30), (0, 0, -30)]


def field(points, positions, normals, phase_steps, p0, k, err_rad):
    """Complex pressure at points (Q, 3) from all transducers."""
    pos = positions.reshape(-1, 3)                     # (288, 3)
    nrm = np.repeat(normals, C.CHANNELS_PER_BOARD, axis=0)
    phi = 2 * np.pi * phase_steps.reshape(-1) / C.PHASE_STEPS + err_rad.reshape(-1)
    r = points[:, None, :] - pos[None, :, :]           # (Q, 288, 3)
    d = np.linalg.norm(r, axis=-1)
    cos_t = np.clip(np.sum(r * nrm[None], axis=-1) / d, -1, 1)
    sin_t = np.sqrt(1 - cos_t ** 2)
    ka = k * PISTON_R * sin_t
    direct = np.where(ka < 1e-6, 1.0, 2 * j1(ka) / np.where(ka < 1e-6, 1, ka))
    direct = np.where(cos_t > 0, direct, 0.0)          # nothing comes out the back
    # e^{+iwt} convention: a delay of phi multiplies by e^{-i phi}
    return np.sum(p0 * direct / d * np.exp(-1j * (k * d + phi[None, :])), axis=1)


def gorkov(p, h, omega, c0):
    """U on a 3D grid of complex pressure p (Nx, Ny, Nz) with spacing h."""
    vol = np.pi * BEAD_D ** 3 / 6
    f1 = 1.0                                           # bead much stiffer than air
    f2 = 2 * (RHO_BEAD - RHO_AIR) / (2 * RHO_BEAD + RHO_AIR)
    gx, gy, gz = np.gradient(p, h)
    p2 = np.abs(p) ** 2 / 2                            # <p^2>
    v2 = (np.abs(gx) ** 2 + np.abs(gy) ** 2 + np.abs(gz) ** 2) / (2 * (RHO_AIR * omega) ** 2)
    return vol * (f1 * p2 / (2 * RHO_AIR * c0 ** 2) - 0.75 * RHO_AIR * f2 * v2)


def check_point(target, solver, p0, err_deg, rng, half=4e-3, h=0.25e-3):
    k = 2 * np.pi / C.WAVELENGTH_M
    omega = 2 * np.pi * C.FREQ_HZ
    steps = solver.steps(target, mode="trap")[0]       # (2, 144) real phase code
    err = np.deg2rad(rng.uniform(-err_deg, err_deg, steps.shape))
    ax = np.arange(-half, half + h / 2, h)
    gx, gy, gz = np.meshgrid(ax + target[0], ax + target[1], ax + target[2], indexing="ij")
    pts = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], axis=1)
    p = np.zeros(len(pts), dtype=complex)
    for s in range(0, len(pts), 4000):                 # chunks keep memory small
        p[s:s + 4000] = field(pts[s:s + 4000], solver.positions, np.array([[0.0, 0.0, 1.0], [0.0, 0.0, -1.0]]),
                              steps, p0, k, err)
    p = p.reshape(gx.shape)
    U = gorkov(p, h, omega, C.SPEED_OF_SOUND)
    i, j, kk = np.unravel_index(np.argmin(U[1:-1, 1:-1, 1:-1]), tuple(n - 2 for n in U.shape))
    i, j, kk = i + 1, j + 1, kk + 1
    found = np.array([gx[i, j, kk], gy[i, j, kk], gz[i, j, kk]])
    offset = np.linalg.norm(found - target)
    # stiffness: second differences of U at the minimum must be positive
    stiff = [U[i + 1, j, kk] + U[i - 1, j, kk] - 2 * U[i, j, kk],
             U[i, j + 1, kk] + U[i, j - 1, kk] - 2 * U[i, j, kk],
             U[i, j, kk + 1] + U[i, j, kk - 1] - 2 * U[i, j, kk]]
    # strongest upward push below the trap, against gravity
    fz = -np.gradient(U, h, axis=2)
    up = fz[i, j, :kk].max() if kk > 0 else 0.0
    weight = RHO_BEAD * np.pi * BEAD_D ** 3 / 6 * 9.81
    ok = offset < 1.5e-3 and min(stiff) > 0 and up > weight
    centre = np.abs(p).max()
    return dict(target=target, found=found, offset=offset, stiff=stiff, up=up,
                weight=weight, ok=ok, pmax=centre, p=p, axis=ax)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--p0", type=float, default=2.0, help="transducer strength, Pa*m")
    ap.add_argument("--err", type=float, default=10.0, help="random phase error, degrees")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--plot", action="store_true")
    args = ap.parse_args(argv)

    solver = PhaseSolver(disabled={"bottom": set(), "top": set()},
                         calibration={"bottom": {}, "top": {}})
    rng = np.random.default_rng(args.seed)
    print(f"288 transducers, gap {C.BOARD_GAP_M * 1000:.0f} mm, {C.PHASE_STEPS} steps, "
          f"+/-{args.err:.0f} deg random error, P0 = {args.p0} Pa*m")
    print(f"{'target (mm)':>20} {'trap found (mm)':>24} {'off':>6} {'up/weight':>10}  result")
    results = []
    for t_mm in TEST_POINTS_MM:
        target = np.array(t_mm, dtype=float) / 1000
        r = check_point(target, solver, args.p0, args.err, rng)
        results.append(r)
        f = r["found"] * 1000
        print(f"{str(t_mm):>20} ({f[0]:+6.2f},{f[1]:+6.2f},{f[2]:+6.2f}) "
              f"{r['offset'] * 1000:5.2f} {r['up'] / r['weight']:10.1f}  "
              f"{'PASS' if r['ok'] else 'FAIL'}")

    if args.plot:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        r = results[0]
        mid = len(r["axis"]) // 2
        ext = [r["axis"][0] * 1000, r["axis"][-1] * 1000] * 2
        plt.imshow(np.abs(r["p"][:, mid, :]).T, origin="lower", extent=ext, cmap="magma")
        plt.colorbar(label="|p| (Pa)")
        plt.xlabel("x (mm)")
        plt.ylabel("z (mm)")
        plt.title("Pressure around the centre trap (x-z slice)")
        plt.savefig("sound_field.png", dpi=150, bbox_inches="tight")
        print("saved sound_field.png")

    passed = all(r["ok"] for r in results)
    print("CHECK 3:", "PASS" if passed else "FAIL")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
