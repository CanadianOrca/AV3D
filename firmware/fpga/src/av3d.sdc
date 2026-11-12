# timing constraints
# tang nano's 27 MHz oscillator on pin 4 (period 37.037 ns)
create_clock -name clk27 -period 37.037 -waveform {0 18.518} [get_ports {clk27}]
