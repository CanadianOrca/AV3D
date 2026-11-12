AV3d - FPGA Firmware (Tang Nano 20k)

One bitstream for both boards; J7 picks TOP or Bottom.

files

src/top.v	Connects everything
src/clocks.v	27 MHz in, power-on reset
src/synchronizer.v, src/debounce.v	Safe inputs, S1 button
src/cycle_timer.v	32 steps per cycle; SYNC out (top) or lock to SYNC (bottom)
src/spi_slave.v	Bytes from the Pi; STATUS / echo / index back
src/cmd_decoder.v	Commands from docs/protocol.md
src/point_ram.v	680 points in block RAM
src/player.v	Plays the points, STEP pulses keep both boards together
src/channel_gen.v	On/off for all 144 channels, plus test modes
src/shift_out.v	Drives the 18 shift registers and /OE
src/led_pwm.v	RGB PWM
src/av3d.cst / src/av3d.sdc	Pin map / 27 MHz clock
build.tcl	Command-line build with gw_sh
sim/ Testbenches and run_sims.py

Simulate: (before every hardware test)

cd firmware/fpga/sim
python run_sims.py
python run_sims.py --wave

BUILD in gowin ide
location firmware/fpga
device series gw2ar package qfn88 speed c8/I7 device version c
add all files in /src to project
config: top module = av3d_top, verilog language = verilog 2001
place & route > dual purpose pin tick use sspi as regular io, use mspi as regular io, use ready as regualr io, use done as regular io
run all (green)
program: tools > programmer (sram program - lost at power off) or external flash mode > exflash erase, program to keep it

