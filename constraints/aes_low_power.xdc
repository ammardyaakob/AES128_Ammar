# Low-power timing constraints for aes_top.
# The implementation flow sets aes_clk_period_ns before reading this file.

create_clock -name aes_clk -period $aes_clk_period_ns [get_ports clk]
