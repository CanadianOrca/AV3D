"""AV3D - raspberry PI side

modules:
config - the locked design numbers
geometry - where all 288 transudcers are, which channel each one is
phases - bead position > phase of every transducers
shapes - shapes and text > smooth point lists
font - single stroke letters used by shapes.text()
protocol - the bytes, sent over SPI
player - uploads shapes to both boards and controls playback
"""


__version__ = "0.1.0"
