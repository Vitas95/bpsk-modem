set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj mac_fir_tb
add wave -group TB sim:/$obj/*

# DUT
set obj mac_fir_tb/dut
add wave -group DUT sim:/$obj/*
add wave -group IN_IF sim:/$obj/s_axis/*
add wave -group OUT_IF sim:/$obj/m_axis/*

configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100