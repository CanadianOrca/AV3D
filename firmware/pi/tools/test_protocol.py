"""Check 6: the bytes exactly match docs/protocol.md."""

import numpy as np
import pytest

from av3d import protocol as P


def test_write_point_layout():
    ch = np.arange(144, dtype=np.uint8) % 32 | 0x80
    msg = P.pack_write_point(679, ch, (1, 2, 3))
    assert len(msg) == P.WRITE_POINT_LEN == 150
    assert msg[0] == 0x01
    assert msg[1:3] == bytes([0x02, 0xA7])                 # 679, high byte first
    assert msg[3:147] == bytes(ch)
    assert msg[147:] == bytes([1, 2, 3])


def test_short_commands():
    assert P.pack_set_count(300) == bytes([0x02, 0x01, 0x2C])
    assert P.pack_set_rate(6) == bytes([0x03, 0x00, 0x06])
    assert P.pack_play() == b"\x04"
    assert P.pack_stop() == b"\x05"
    assert P.pack_off() == b"\x06"
    assert P.pack_show(678) == bytes([0x07, 0x02, 0xA6])
    assert P.pack_set_trim(5) == bytes([0x08, 0x05])
    assert P.pack_test(2) == bytes([0x09, 0x02])
    assert P.pack_get_index() == bytes([0x0A, 0x00, 0x00])
    assert P.pack_nop(b"\x11\x22") == bytes([0x00, 0x11, 0x22])


def test_range_checks():
    with pytest.raises(ValueError):
        P.pack_write_point(680, bytes(144))
    with pytest.raises(ValueError):
        P.pack_write_point(0, bytes(143))
    with pytest.raises(ValueError):
        P.pack_show(-1)
    with pytest.raises(ValueError):
        P.pack_test(4)
    with pytest.raises(ValueError):
        P.pack_set_rate(70000)


def test_status_parse():
    s = P.parse_status(0xA0 | 0x10 | 0x04 | 0x01)
    assert s.valid and s.is_top and s.outputs_on and s.sync_ok
    assert not s.playing and not s.test
    assert not P.parse_status(0xFF).valid                  # floating MISO reads 0xFF
    assert not P.parse_status(0x00).valid


def test_pretend_link_echo_and_index():
    link = P.PretendLink()
    sent = P.pack_nop(b"\x10\x20\x30")
    reply = link.transfer("top", sent)
    assert P.parse_status(reply[0]).is_top
    assert reply[1:] == list(sent[:-1])
    link.index["bottom"] = 0x123
    r = link.transfer("bottom", P.pack_get_index())
    assert (r[1] << 8 | r[2]) == 0x123
