create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
create_clock -name AUD_BCLK -period 320.000 [get_ports {AUD_BCLK}]
derive_pll_clocks -create_base_clocks
derive_clock_uncertainty
# The audio bit clock, 50 MHz clock and VGA pixel clock only exchange slowly-changing, double-registered values.
set_clock_groups -asynchronous -group {CLOCK_50} -group {AUD_BCLK}
set_false_path -from [get_clocks {CLOCK_50}] -to [get_clocks {*vgacs0*}]
set_false_path -from [get_clocks {*vgacs0*}] -to [get_clocks {CLOCK_50}]
