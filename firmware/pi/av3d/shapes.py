"""
Shapes and text > smooth closed point lists the bead can follow

every shape is a closed loop so that the fpga plays the points round
Points are spaced as evenly as possible, so bead moves at a steady speed and sharp corners
should be rounded off, tbd.

each function returns (points, lit)
points (n,3) float, meters
lit (n,) bool, false where the leds should be dark (moves)
make() adds colours and checks the safety

2d shapes are drawn in the x-z plane by default: vertical plane the viewer looks at
"""

import numpy as np
from . import config as C
from . import font

DEFAULT_COLOUR = (180, 180, 180)

# helpers
def path_length(points, closed=True):
    p = np.asarray(points, dtype=float)
    if closed:
        p = np.vstack([p, p[0]])
    return np.sum(np.linalg.norm(np.diff(p, axis=0), axis=1))

def resample(points, n, lit=None, closed=True):
    p = np.asarray(points, dtype=float)
    k = len(p)
    if lit is None:
        lit = np.ones(k, dtype=bool)
    if closed:
        p = np.vstack([p, p[:1]])
        seg_lit = lit[:k]
    else:
        seg_lit = lit[:k - 1]
    seg = np.linalg.norm(np.diff(p, axis=0), axis=1)
    cum = np.concatenate(([0.0], np.cumsum(seg)))
    total = cum[-1]
    if total <= 0:
        return np.repeat(p[:1], n, axis=0), np.ones(n, dtype=bool)
    s = np.arange(n) * total / n if closed else np.linspace(0.0, total, n)
    idx = np.clip(np.searchsorted(cum, s, side="right") - 1, 0, len(seg) - 1)
    t = np.where(seg[idx] > 0, (s - cum[idx]) / np.where(seg[idx] > 0, seg[idx], 1), 0.0)
    out = p[idx] + (p[idx + 1] - p[idx]) * t[:, None]
    return out, seg_lit[idx]

def smooth(points, window=9):
    p = np.asarray(points, dtype=float)
    if window <= 1 or len(p) < window:
        return p.copy()
    h = window // 2
    padded = np.vstack([p[-h:], p, p[:h]])
    kernel = np.ones(window) / window
    return np.stack([np.convolve(padded[:, i], kernel, mode="valid") for i in range(3)], axis=1)

def _plane(u, v, plane, center):
    u, v = np.asarray(u, float), np.asarray(v, float)
    zero = np.zeros_like(u)
    if plane== "xz":
        pts = np.stack([u, zero, v], axis=1)
    elif plane == "xy":
        pts = np.stack([u, v, zero], axis=1)
    elif plane == "yz":
        pts = np.stack([zero, u, v], axis=1)
    else:
        raise ValueError("plane must be 'xz', 'xy', or 'yz'")
    return pts + np.asarray(center, float)

def _finish(points, n, lit=None, corner_mm=3.0):
    dense_n = max(4 * n, 400)
    pts, lit_d = resample(points, dense_n, lit)
    spacing = path_length(pts) / dense_n
    window = int(round((corner_mm * 1e-3) / max(spacing, 1e-9))) | 1
    pts = smooth(pts, min(window, dense_n // 4 | 1))
    return resample(pts, n, lit_d)

# shapes
def point(pos=(0.0, 0.0, 0.0), n=1):
    pts = np.repeat(np.asarray(pos, float)[None, :], n, axis=0)
    return pts, np.ones(n, dtype=bool)


def circle(radius=0.020, n=C.MAX_SHAPE_POINTS, plane="xz", center=(0, 0, 0)):
    a = 2 * np.pi * np.arange(n) / n
    return _plane(radius * np.cos(a), radius * np.sin(a), plane, center), np.ones(n, bool)


def square(side=0.030, n=C.MAX_SHAPE_POINTS, plane="xz", center=(0, 0, 0), corner_mm=4.0):
    h = side / 2
    u = np.array([-h, h, h, -h])
    v = np.array([-h, -h, h, h])
    return _finish(_plane(u, v, plane, center), n, corner_mm=corner_mm)


def triangle(side=0.035, n=C.MAX_SHAPE_POINTS, plane="xz", center=(0, 0, 0), corner_mm=4.0):
    r = side / np.sqrt(3)
    a = - np.pi / 2 + 2 * np.pi * np.arange(3) / 3
    return _finish(_plane(r * np.cos(a), r * np.sin(a), plane, center), n, corner_mm=corner_mm)

def star(radius=0.022, n=C.MAX_SHAPE_POINTS, plane="xz", center=(0, 0, 0), corner_mm=4.0):
    a = np.pi / 2 + np.pi * np.arange(10) / 5
    r = np.where(np.arange(10) % 2 == 0, radius, radius * 0.382)
    return _finish(_plane(r * np.cos(a), r * np.sin(a), plane, center), n, corner_mm=corner_mm)

def figure8(size=0.025, n=C.MAX_SHAPE_POINTS, plane="xz", center=(0, 0, 0)):
    t = 2 * np.pi * np.arange(n) / n
    return _plane(size * np.sin(t), size * np.sin(t) * np.cos(t), plane, center), np.ones(n, bool)

def lissajous(ax=0.020, ay=0.020, fx=3, fy=2, phase=np.pi / 2, n=C.MAX_SHAPE_POINTS, plane="xz", center=(0, 0, 0)):
    t = 2 * np.pi * np.arange(n) / n
    return _plane(ax * np.sin(fx * t + phase), ay * np.sin(fy * t), plane, center), np.ones(n, bool)

def spiral(radius=0.018, height=0.040, turns=3, n=C.MAX_SHAPE_POINTS, center=(0, 0, 0)):
    half = n // 2
    t = np.linspace(0, 1, half, endpoint=False)
    t = np.concatenate([t, 1 - t])[:n]
    if len(t) < n:
        t = np.concatenate([t, t[-1:]])
    a = 2 * np.pi * turns * t
    pts = np.stack([radius * np.cos(a), radius * np.sin(a), (t - 0.5) * height], axis=1)
    return pts + np.asarray(center, float), np.ones(n, bool)

def cube_edges(side=0.030, n=C.MAX_SHAPE_POINTS, center=(0, 0, 0), corner_mm=3.0):
    h = side / 2
    v = np.array([[-h, -h, -h], [h, -h, -h], [h, h, -h], [-h, h, -h],
                  [-h, -h, h], [h, -h, h], [h, h, h], [-h, h, h]])
    order = [0, 1, 2, 3, 0, 4, 5, 1, 5, 6, 2, 6, 7, 3, 7, 4]
    return _finish(v[order] + np.asarray(center, float), n, corner_mm=corner_mm)

def text(string, width=0.070, n=C.MAX_SHAPE_POINTS, center=(0, 0, 0), corner_mm=1.5, max_height=0.035):
    strokes = [s for s in font.strokes_for(string) if s]
    if not strokes:
        return point(center, n)
    w_units = font.text_width_units(string)
    scale = min(width / w_units, max_height / font.GLYPH_H)
    pts, lit = [], []
    for stroke in strokes:
        for j, (x, y) in enumerate(stroke):
            pts.append(((x - w_units / 2) * scale, 0.0, (y - font.GLYPH_H / 2) * scale))
            lit.append(j < len(stroke) - 1)
    pts = np.asarray(pts) + np.asarray(center, float)
    return _finish(pts, n, np.asarray(lit), corner_mm=corner_mm)

SHAPES = {
    "point" : point,
    "circle" : circle,
    "square" : square,
    "triangle" : triangle,
    "star" : star,
    "figure8" : figure8,
    "lissajous" : lissajous,
    "spiral" : spiral,
    "cube" : cube_edges,
    "text" : text,
}

def make(name, n=C.MAX_SHAPE_POINTS, colour=DEFAULT_COLOUR,**kwargs):
    from .phases import check_in_limits
    if name not in SHAPES:
        raise ValueError(f"unknown shape: {name!r}; choose from {', '.join(SHAPES)}")
    if not 1 <= n <= C.MAX_SHAPE_POINTS:
        raise ValueError(f"n must be between 1 and {C.MAX_SHAPE_POINTS}, got {n}")
    pts, lit = SHAPES[name](n=n, **kwargs)
    check_in_limits(pts)
    rgb = np.zeros((len(pts), 3), dtype=np.uint8)
    rgb[lit] = np.asarray(colour, dtype=np.uint8)
    return pts, rgb
