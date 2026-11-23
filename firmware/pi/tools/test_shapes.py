import numpy as np
import pytest

from av3d import config as C
from av3d import shapes as S


@pytest.mark.parametrize("name", [n for n in S.SHAPES if n != "text"])
def test_every_shape_builds_inside_limits(name):
    pts, rgb = S.make(name)
    assert pts.shape == (C.MAX_SHAPE_POINTS, 3)
    assert rgb.shape == (C.MAX_SHAPE_POINTS, 3) and rgb.dtype == np.uint8
    assert np.all(np.isfinite(pts))


def test_even_spacing_on_circle():
    pts, _ = S.circle(0.02, n=200)
    gaps = np.linalg.norm(np.diff(np.vstack([pts, pts[:1]]), axis=0), axis=1)
    assert gaps.max() / gaps.min() < 1.01


def test_square_corners_are_rounded_and_spacing_even():
    pts, _ = S.square(0.03, n=400)
    gaps = np.linalg.norm(np.diff(np.vstack([pts, pts[:1]]), axis=0), axis=1)
    assert gaps.max() / gaps.mean() < 1.1
    # no point reaches the sharp corner at (+15, +15) mm
    corner = np.array([0.015, 0.0, 0.015])
    assert np.min(np.linalg.norm(pts - corner, axis=1)) > 0.5e-3


def test_resample_count_and_closed_loop():
    sq = np.array([[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], float)
    out, lit = S.resample(sq, 40)
    assert out.shape == (40, 3) and lit.all()
    assert np.isclose(S.path_length(out), 4.0, rtol=0.01)


def test_text_has_dark_travel_moves():
    pts, rgb = S.make("text", string="HI", colour=(255, 0, 0))
    lit = rgb.any(axis=1)
    assert lit.sum() > 0.4 * len(lit)          # mostly drawing
    assert (~lit).sum() > 0                    # but some dark moves between strokes
    assert np.all(rgb[lit] == (255, 0, 0))


def test_unknown_shape_and_glyph():
    with pytest.raises(ValueError):
        S.make("hexagon")
    with pytest.raises(ValueError):
        S.make("text", string="~")


def test_cube_visits_all_corners():
    pts, _ = S.cube_edges(0.03)
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                c = 0.015 * np.array([sx, sy, sz])
                assert np.min(np.linalg.norm(pts - c, axis=1)) < 3e-3
