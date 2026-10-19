set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj farrow_filter_tb
add wave -group TB sim:/$obj/sys/*
add wave -group TB sim:/$obj/data_in/*
add wave -group TB sim:/$obj/data_out/*

# DUT
set obj farrow_filter_tb/dut/farrow_filter_i
add wave -group DUT sim:/$obj/*

# Horner MAC
set obj farrow_filter_tb/dut/farrow_filter_i/horner_mac_inst
add wave -group HORNER_MAC sim:/$obj/*

configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100