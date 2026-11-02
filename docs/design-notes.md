Things we will need to follow to ensure that our designs are standardized with each other.

- Transducers per board: 100-144, 10mm transducers with .5mm gap
- Board spacing: about 135 mm (whatever works in CAD)
- Sound frequency: 40kHz
- Phase steps: around 32 per cycle, TBD later on
- Shift registers: 18 x 74AHC595 per board, so each FPGA only needs 18 data pins
- Shift clock: 10.24 MHz (8 channels x 32 steps x 40 kHz), every channel gets updated 32 times per cycle
- Drivers: One TC4428A per transducers, one output is inverted so transducers see twice the supply voltage
- Drive supply: 12V from adapter
- Logic voltage: 3.3V everywhere, Tang Nano can only take 3.3V only not 5V
- Keeping boards in step: Top board FPGA to send a 40kHz sync singal to the bottom board
- Shape memory: each point is around 144 bytes of storage, the FPGA's block ram holds around 700 points, just enough for 0.1s for each shape
- Top board only, 3 MOSFETS for rgb