"""the bytes and the spi link that carries them

one command per spi transaction, spi mode 0, msb first.
bottom board = /dev/spidev0.0, top board = /dev/spidev0.1

use spilink on pi and pretendlink on a laptop: pretendlink records every
transaction (and prints with verbose), so all code can be written
and tested before the boards even exist.

"""

from dataclasses import dataclass
import numpy as np
from . import config as C

CMD_NOP = 0x00
CMD_WRITE_POINT = 0x01
CMD_SET_COUNT = 0x02
CMD_SET_RATE = 0x03
CMD_PLAY = 0x04
CMD_STOP = 0x05
CMD_OFF = 0x06
CMD_SHOW = 0x07
CMD_SET_TRIM = 0x08
CMD_TEST = 0x09
CMD_GET_INDEX = 0x0A

WRITE_POINT_LEN = 150
STATUS_MAGIC_MASK = 0xE0
STATUS_MAGIC = 0xA0

# packing
def _u16(v):
    v = int(v)
    if not 0 <= v <= 0xFFFF:
        raise ValueError("value out of range for u16")
    return bytes([v >> 8, v & 0xFF])

def pack_write_point(idx, channel_bytes, rgb=(0, 0, 0)):
    if not 0 <= idx < C.MAX_POINTS:
        raise ValueError(f"point index {idx} out of range-{C.MAX_POINTS - 1}")
    ch = bytes(np.asarray(channel_bytes, dtype=np.uint8).tobytes())
    if len(ch) !=C.CHANNELS_PER_BOARD:
        raise ValueError(f"need {C.CHANNELS_PER_BOARD} channel bytes, got {len(ch)}")
    r, g, b = (int(x) & 0xFF for x in rgb)
    return bytes([CMD_WRITE_POINT]) + _u16(idx) + ch + bytes([r, g, b])

def pack_set_count(n):
    return bytes([CMD_SET_COUNT]) + _u16(n)

def pack_set_rate(cycles_per_point):
    return bytes([CMD_SET_RATE]) + _u16(cycles_per_point)

def pack_play():
    return bytes([CMD_PLAY])

def pack_stop():
    return bytes([CMD_STOP])

def pack_off():
    return bytes([CMD_OFF])

def pack_show(idx):
    if not 0 <= idx < C.MAX_POINTS:
        raise ValueError(f"point index {idx} out of range")
    return bytes([CMD_SHOW]) + _u16(idx)

def pack_set_trim(ticks):
    return bytes([CMD_SET_TRIM, int(ticks) & 0xFF])

def pack_test(mode):
    if mode not in (0, 1, 2, 3):
        raise ValueError("test mode is 0 (off), 1, 2, or 3")
    return bytes([CMD_TEST, mode])

def pack_get_index():
    return bytes([CMD_GET_INDEX, 0x00, 0x00])

def pack_nop(extra=b""):
    return bytes([CMD_NOP]) + bytes(extra)

# replies
@dataclass
class Status:
    raw: int
    is_top: bool
    playing: bool
    outputs_on: bool
    test: bool
    sync_ok: bool

    @property
    def valid(self):
        return (self.raw & STATUS_MAGIC_MASK) == STATUS_MAGIC

    def __str__(self):
        if not self.valid:
            return f"no board answering (got 0x{self.raw:02X})"
        return (f"{'TOP' if self.is_top else 'BOTTOM'} board: "
                f"{'playing' if self.playing else 'not playing'}, "
                f"outputs {'ON' if self.outputs_on else 'off'}, "
                f"test {'on' if self.test else 'off'}, "
                f"sync {'ok' if self.sync_ok else 'MISSING'}")

def parse_status(byte):
    b = int(byte)
    return Status(raw=b, is_top=bool(b & 1), playing=bool(b & 2), outputs_on=bool(b & 4), test=bool(b & 8), sync_ok=bool(b & 16))

def expected_echo(sent):
    return list(sent[:-1])

# link
class Link:

    def write(self, board, data):
        raise NotImplementedError

    def transfer(self, board, data):
        raise NotImplementedError

    def close(self):
        pass

class SpiLink(Link):

    def __init__(self, bus=C.SPI_BUS, ce=None, write_hz=C.SPI_WRITE_HZ, read_hz=C.SPI_READ_HZ):
        import spidev # only exists on the Pi
        if write_hz > 4_000_000:
            raise ValueError("SPI must be 4 MHz or less")
        self.read_hz = read_hz
        self.devs = {}
        for board, cs in (ce or C.SPI_CE).items():
            dev = spidev.SpiDev()
            dev.open(bus, cs)
            dev.mode = 0
            dev.bits_per_word = 8
            dev.max_speed_hz = write_hz
            self.devs[board] = dev

    def write(self, board, data):
        self.devs[board].writebytes2(bytes(data))

    def transfer(self, board, data):
        return list(self.devs[board].xfer2(list(data), self.read_hz))

    def close(self):
        for dev in self.devs.values():
            dev.close()


class PretendLink(Link):

    def __init__(self, verbose=False):
        self.verbose = verbose
        self.log = []
        self.index = {"bottom": 0, "top": 0}

    def write(self, board, data):
        data = bytes(data)
        self.log.append((board, data))
        if self.verbose:
            print(f"[pretend] {board:6s} -> {data[:12].hex(' ')}"
                  f"{' ...' if len(data) > 12 else ''} ({len(data)} bytes)")

    def transfer(self, board, data):
        self.write(board, data)
        status = 0xA0 | 0x10 | (1 if board == "top" else 0)
        reply = [status] + list(data[:-1])
        if data and data[0] == CMD_GET_INDEX:
            i = self.index[board]
            reply[1:3] = [i >> 8, i & 0xFF]
        return reply[:len(data)]

    def commands(self, board=None):
        return [d[0] for b, d in self.log if board in (None, b)]
