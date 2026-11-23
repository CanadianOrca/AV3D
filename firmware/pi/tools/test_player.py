"""Player in pretend mode: order rules, live slots and uploads."""

import numpy as np
import pytest

from av3d import config as C
from av3d import protocol as P
from av3d import shapes as S
from av3d.player import Player


@pytest.fixture
def player():
    return Player(P.PretendLink(), sleep=lambda s: None)


def boards_for(link, code):
    return [b for b, d in link.log if d[0] == code]


def test_play_goes_bottom_first_and_stop_top_first(player):
    player.play()
    player.stop()
    assert boards_for(player.link, P.CMD_PLAY) == ["bottom", "top"]
    assert boards_for(player.link, P.CMD_STOP) == ["top", "bottom"]


def test_upload_writes_every_point_to_both_boards(player):
    pts, rgb = S.make("circle", n=50)
    player.upload(pts, rgb)
    writes = [(b, d) for b, d in player.link.log if d[0] == P.CMD_WRITE_POINT]
    assert len(writes) == 100
    assert all(len(d) == 150 for _, d in writes)
    idx = sorted({(d[1] << 8) | d[2] for _, d in writes})
    assert idx == list(range(50))
    counts = [d for _, d in player.link.log if d[0] == P.CMD_SET_COUNT]
    assert counts == [P.pack_set_count(50)] * 2
    # the two boards get different phases (top has the extra half cycle)
    bot = next(d for b, d in writes if b == "bottom")
    top = next(d for b, d in writes if b == "top")
    assert bot[3:147] != top[3:147]


def test_hold_alternates_live_slots(player):
    player.hold((0, 0, 0))
    player.hold((0.001, 0, 0))
    shows = [((d[1] << 8) | d[2]) for b, d in player.link.log if d[0] == P.CMD_SHOW and b == "top"]
    assert shows == list(C.LIVE_SLOTS)
    writes = [((d[1] << 8) | d[2]) for b, d in player.link.log
              if d[0] == P.CMD_WRITE_POINT and b == "top"]
    assert writes == list(C.LIVE_SLOTS)        # each slot written before it is shown


def test_move_to_takes_small_steps(player):
    player.move_to((0.01, 0, 0), speed=0.02, update_hz=100)   # 10 mm at 0.2 mm/step
    shows = [d for b, d in player.link.log if d[0] == P.CMD_SHOW and b == "top"]
    assert len(shows) == 50
    assert np.allclose(player.position, (0.01, 0, 0))


def test_nudge_is_clipped_to_safe_box(player):
    player.position = np.array([C.LIMIT_XY_M, 0, 0])
    player.nudge(dx=0.01)
    assert player.position[0] == pytest.approx(C.LIMIT_XY_M)


def test_rate_and_loop_time(player):
    pts, rgb = S.make("circle")
    player.upload(pts, rgb)
    r = player.rate_for_loop_time(0.1)
    assert r == 6                               # 678 points * 6 / 40 kHz = 0.1017 s
    player.set_rate(r)
    assert player.loop_time() == pytest.approx(0.1017, abs=1e-3)
    assert 0.5 < player.bead_speed() < 1.5      # 20 mm circle, ~1.2 m/s


def test_start_shape_ramps_down_to_target(player):
    pts, rgb = S.make("circle")
    target = player.start_shape(pts, rgb, loop_time=0.1)
    rates = [(d[1] << 8 | d[2]) for b, d in player.link.log if d[0] == P.CMD_SET_RATE and b == "top"]
    assert rates[0] == target * 10 and rates[-1] == target
    assert rates == sorted(rates, reverse=True)


def test_echo_and_status_in_pretend(player):
    st = player.status()
    assert st["top"].is_top and not st["bottom"].is_top
    status, bad = player.echo_test("bottom", 32, seed=1)
    assert status.valid and bad == []


def test_start_shape_never_exceeds_speed_limit(player):
    pts, rgb = S.make("text", string="AV3D")       # long path with travel moves
    player.start_shape(pts, rgb, loop_time=0.05)   # asks for far too fast
    assert player.bead_speed() <= C.MAX_SPEED_M_S + 1e-9
    assert player.rate == player.min_rate()
