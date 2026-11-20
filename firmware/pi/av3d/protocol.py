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

def pack_write_point(idx, channel_bytes, rgb=)
