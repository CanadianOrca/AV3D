"""
Where every transducer is and which channel drives it

channel map
CH n = transducers X n = driver U(100+n)
bank b = (n-1) // 8 > shift register U(10+b), FPGA DATA (b+1)
local i = (n-1) % 8 > QA-QH of that shift register
block row = b // 3, block col = b % 3 (6 rows of 3 blocks)
row = 2 * block_row + i // 4 (0 = top edge)
col = 4 * block_col + i % 4 (0 = left edge)

board-local position, seen from front: x = (col - 5.5) * pitch,
y = (5.5 - row) * pitch
i am too lazy to explain rest <3
"""

import numpy as np

from . import config as C

BOARDS = ("bottom", "top")

def channel_to_rowcol (ch):
    if not 1 <= ch <= C.CHANNELS_PER_BOARD:
        raise ValueError(f"channel {ch} out of range")
    n = ch - 1
    bank, local = divmod(n, C.CH_PER_BANK)
    block_row, block_col = divmod(bank, C.BANK_GRID_COLS)
    row = C.BANK_BLOCK_ROWS * block_row + local // C.BANK_BLOCK_COLS
    col = C.BANK_BLOCK_COLS * block_col + local % C.BANK_BLOCK_COLS
    return row, col

def rowcol_to_channel(row, col):
    if not (0 <= row < C.GRID_N and 0 <= col < C.GRID_N):
        raise ValueError(f"row {row} or col {col} out of range")
    block_row, r_in = divmod(row, C.BANK_BLOCK_ROWS)
    block_col, c_in = divmod(col, C.BANK_BLOCK_COLS)
    bank = block_row * C.BANK_GRID_COLS + block_col
    local = r_in * C.BANK_BLOCK_COLS + c_in
    return bank * C.CH_PER_BANK + local + 1

def channel_bank(ch):
    bank, local = divmod(ch - 1, C.CH_PER_BANK)
    return bank + 1, "Q" + "ABCDEFGH"[local]

def local_xy(ch, pitch=C.PITCH_M):
    row, col = channel_to_rowcol(ch)
    half = (C.GRID_N - 1) / 2
    return (col - half) * pitch, (half - row) * pitch

def board__position(board, gap=C.BOARD_GAP_M, pitch=C.PITCH_M, flip=C.TOP_FLIP_AXIS):
    pos = np.zeros((C.CHANNELS_PER_BOARD, 3))
    for k in range(C.CHANNELS_PER_BOARD):
        x, y = local_xy(k + 1, pitch=pitch)
        if board == "bottom":
            pos[k] = (x, y, -gap / 2)
        elif board == "top":
            if flip == "x":
                pos[k] = (-x, y, gap / 2)
            elif flip == "y":
                pos[k] = (x, -y, gap / 2)
            else:
                raise ValueError("flip must be on x or y")
        else:
            raise ValueError(f"unknown board {board}")
    return pos

def all_positions(gap=C.BOARD_GAP_M, pitch=C.PITCH_M, flip=C.TOP_FLIP_AXIS):
    return np.stack([board__position(b, gap, pitch, flip) for b in BOARDS])

def channel_table():
    rows = []
    for ch in range(1, C.CHANNELS_PER_BOARD + 1):
        bank, q = channel_bank(ch)
        r, c = channel_to_rowcol(ch)
        rows.append((ch, bank, q, r, c))
    return rows

if __name__ == "__main__":
    print("Channel numbers, front view (row 0 at top, Tang Nano strip on right)")
    for r in range(C.GRID_N):
        print(" ".join(f"{rowcol_to_channel(r, c):3d}" for c in range(C.GRID_N)))
