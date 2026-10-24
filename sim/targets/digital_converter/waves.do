set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj digital_converter_tb
add wave -group TB sim:/$obj/sys/*

# DUT_UP
set obj digital_converter_tb/dut_0
add wave -group DUT_UP sim:/$obj/*
add wave -group DUT_UP sim:/$obj/s_axis/*
add wave -group DUT_UP sim:/$obj/m_axis/*

# DUT_DOWN
set obj digital_converter_tb/dut_1
add wave -group DUT_DOWN sim:/$obj/*
add wave -group DUT_DOWN sim:/$obj/s_axis/*
add wave -group DUT_DOWN sim:/$obj/m_axis/*

configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100