# AV3D tests: how to run them and what they check

Made by Claude (AI), like every file in this folder (see README.md). Test use only.

## How to run

Needs Icarus Verilog (iverilog and vvp on PATH) and Python 3.8 or newer.
The Pi tests also need `pip install -r firmware/pi/requirements-dev.txt` (numpy, pytest, scipy).

    cd firmware/fpga/sim
    python run_sims.py              every test (a few minutes)
    python run_sims.py --quick      skips the slow ones (about 30 seconds)
    python run_sims.py --wave       also saves waveforms in build/ (open the .vcd files with GTKWave)
    python run_sims.py --fpga-only  only the Verilog testbenches
    python run_sims.py board        only the tests with "board" in their name

It ends with a table and "ALL TESTS PASSED", or the number of tests that failed.
The full output of every test is saved in build/ (see the end of this file).

## What each test checks

| File | Checks |
|---|---|
| tb_channel_gen.v | every channel at every one of the 32 steps: phase rule, on bit, enable, test modes 1-3 |
| tb_shift_out.v | the 18 shift registers latch the right pattern every step, QA = first channel of a bank, SRCLK/RCLK timing, /OE only after the registers hold real data |
| tb_cycle_timer.v | 675 ticks per cycle (40 kHz), 21/22-tick steps, SYNC wave, bottom board locks to SYNC with crystals 200 ppm off, SET_TRIM, losing and getting SYNC back |
| tb_spi_slave.v | 4 MHz writes, 1 MHz reads, STATUS byte, echo, GET_INDEX, a transaction cut off half-way |
| tb_cmd_decoder.v | every command: WRITE_POINT packing into point_ram, index limits, cut-off commands, SET_COUNT / SET_RATE / SET_TRIM limits, TEST, SHOW, PLAY, STOP, OFF |
| tb_led_pwm.v | LED duty cycle, 13 kHz PWM, enable, the LED test pattern |
| tb_board.v | one whole board over SPI: point order, rate, STEP pulse widths, STOP, the two live slots (SHOW), test patterns, OFF, STATUS, GET_INDEX; a bottom board with no SYNC cable stays off |
| tb_button.v | S1 button with the real 9.7 ms debounce: bounce and short glitches ignored, one step per press |
| tb_system.v | two boards linked by SYNC and STEP, bottom crystal +200 and -200 ppm: every output of all 288 channels, same point on both boards, unplugging and replugging the cables, PLAY in either order |
| tb_vectors.v | the bytes made by the real Pi code (firmware/pi/tools/make_vectors.py) played into two boards: stored points, count, rate and every output must match what the Pi code meant |
| hc595.v | a model of one 74AHC595, used by the tests above |
| tb_report.vh | shared by the tests: writes every result line to the screen and to a results file that run_sims.py reads |
| run_sims.py | runs all of the above, plus the Pi unit tests (firmware/pi/tools/test_*.py) and the sound simulation (firmware/pi/tools/sound_sim.py) |

## Made when the tests run (not in git)

- build/: compiled simulations, the simulator's screen output (`<nn>_<test>.log`), the results each test wrote (`<nn>_<test>_results.txt`), waveforms
- vectors/, vectors_2b/: byte files written by make_vectors.py
