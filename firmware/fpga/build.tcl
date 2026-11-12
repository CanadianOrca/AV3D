# command line build with gowin gw_sh (same result as ide)
# windows run c:\gowin\gowinedu\ide\bin\gw_sh.exe build.tcl
# run from firmware/fpga directory
# output bitstream: impl/pnr/av3d.fs

set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7

add_file src/clocks.v
add_file src/synchronizer.v
add_file src/debounce.v
add_file src/cycle_timer.v
add_file src/spi_slave.v
add_file src/cmd_decoder.v
add_file src/point_ram.v
add_file src/player.v
add_file src/channel_gen.v
add_file src/shift_out.v
add_file src/led_pwm.v
add_file src/top.v
add_file src/av3d.cst
add_file src/av3d.sdc

set_option -top_module av3d_top
set_option -verilog_std v2001
set_option -output_base_name av3d
# pins that double as config pins must also be released to GPIO
set_option -use_mspi_as_gpio 1
set_option -use_sspi_as_gpio 1
set_option -use_ready_as_gpio 1
set_option -use_done_as_gpio 1
set_option -rw_check_on_ram 1

run all
