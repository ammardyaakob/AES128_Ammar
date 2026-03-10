# Implementation-only low-power constraints for aes_top.

# rst is used as an asynchronous control input, not part of normal datapath timing.
set_false_path -from [get_ports rst] -to [all_registers]

# Note:
# Vectorless power analysis already applies a default switching model. The
# earlier custom set_switching_activity assumptions were removed from the active
# flow because Vivado rejected them in this out-of-context build.
