import numpy as np
import pytest

from av3d import config as C
from av3d import geometry as G


def test_channel_map_is_one_to_one():
    seen = set()
    for ch in range(1, 145):
        r, c = G.channel_to_rowcol(ch)
        assert 0 <= r < 12 and 0 <= c < 12
        assert G.rowcol_to_channel(r, c) == ch
        seen.add((r, c))
    assert len(seen) == 144


def test_bank_layout_matches_design_notes():
    # bank 1 = CH1..8 = top-left 2x4 block; QA = CH1 at row 0 col 0
    assert G.channel_to_rowcol(1) == (0, 0)
    assert G.channel_to_rowcol(4) == (0, 3)
    assert G.channel_to_rowcol(5) == (1, 0)
    assert G.channel_to_rowcol(8) == (1, 3)
    # bank 2 starts at col 4, bank 4 starts the second block row
    assert G.channel_to_rowcol(9) == (0, 4)
    assert G.channel_to_rowcol(25) == (2, 0)
    # last channel is bottom-right
    assert G.channel_to_rowcol(144) == (11, 11)
    assert G.channel_bank(1) == (1, "QA")
    assert G.channel_bank(8) == (1, "QH")
    assert G.channel_bank(144) == (18, "QH")


def test_positions_and_spacing():
    pos = G.all_positions()
    assert pos.shape == (2, 144, 3)
    assert np.allclose(pos[0, :, 2], -C.BOARD_GAP_M / 2)
    assert np.allclose(pos[1, :, 2], C.BOARD_GAP_M / 2)
    # array is centred on the axis
    assert np.allclose(pos[0, :, :2].mean(axis=0), 0, atol=1e-12)
    # nearest neighbours are one pitch apart
    a = pos[0, G.rowcol_to_channel(3, 3) - 1]
    b = pos[0, G.rowcol_to_channel(3, 4) - 1]
    assert np.isclose(np.linalg.norm(a - b), C.PITCH_M)


def test_top_board_is_flipped_over_x():
    bot = G.board_position("bottom", flip="x")
    top = G.board_position("top", flip="x")
    assert np.allclose(top[:, 0], bot[:, 0])           # x kept
    assert np.allclose(top[:, 1], -bot[:, 1])          # y mirrored
    top_y = G.board_position("top", flip="y")
    assert np.allclose(top_y[:, 0], -bot[:, 0])


def test_bad_channel_raises():
    with pytest.raises(ValueError):
        G.channel_to_rowcol(0)
    with pytest.raises(ValueError):
        G.channel_to_rowcol(145)
