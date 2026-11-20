"""
    Configuration for AV3D - raspberry PI side

units: meters, seconds, hertz. coordinates: origin at centre of the gap between boards,
z points up from the bottom to top
"""

import json
from pathlib import Path

# array
GRID_N = 12 # 12 x 12 transducers per board
PITCH_M = 10.5e-3 # centre-to-centre spacing
BOARD_GAP_M = 0.135 # transducer boards gap
CHANNELS_PER_BOARD = GRID_N * GRID_N # total channels per board
BANKS = 18 # 74AHC595 per board
CH_PER_BANK = 8
BANK_BLOCK_ROWS = 2 # EACH BANK IS 2 x 4 block of transducer
BANK_BLOCK_COLS = 4
BANK_GRID_COLS = 3 # blocks are laid out 3 across
BANK_GRID_ROWS = 2 # blocks are laid out 6 down

# the board sits with pcbs facing each other vertically. use y if frame flips it other way

TOP_FLIP_AXIS = "x"

# sound
FREQ_HZ = 40_000
AIR_TEMP_C = 20.0
SPEED_OF_SOUND = 331.3 + 0.606 * AIR_TEMP_C
WAVELENGTH_M = SPEED_OF_SOUND / FREQ_HZ
PHASE_STEPS = 32
TRAP_OFFSET_STEPS = PHASE_STEPS // 2

# FPGA
FPGA_CLOCK_HZ = 27_000_000
TICKS_PER_CYCLE = FPGA_CLOCK_HZ // FREQ_HZ # 675
MAX_POINTS = 680 # point slots in each fpga
LIVE_SLOTS = (678, 679) # slots reserved for live updates
MAX_SHAPE_POINTS = 678 # shapes use slots 0-677
DEFAULT_RATE = 6 # 40 khz cycles per point > 6667 points/s
MIN_RATE = 1
MAX_RATE = 66535
DEFAULT_SYNC_TRIM = 3 # bottom board SYNC offset in 27 mhz ticks

# SPI
SPI_BUS = 0
SPI_CE = {"bottom": 0, "top": 1} # j8 shunt: bottom on ce0 top on ce1
SPI_WRITE_HZ = 4_000_000
SPI_READ_HZ = 1_000_000 # miso

# SAFETY
LIMIT_XY_M = 0.040
LIMIT_Z_M = 0.050
MAX_SPEED_M_S = 1.5 # player warns above this speed

# per unit fixes
DISABLED_CHANNELS = {"bottom": set(), "top": set()}

CAL_FILE = Path(__file__).with_name("calibration.json")

def load_calibration(path=CAL_FILE):
    cal = {"bottom": {}, "top": {}}
    path = Path(path)
    if path.exists():
        raw = json.loads(path.read_text())
        for board in ("bottom", "top"):
            for ch, steps in raw.get(board, {}).items():
                cal[board][int(ch)] = int(steps)
    return cal
