"""Lets the tests import av3d without installing it (run pytest from firmware/pi)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
