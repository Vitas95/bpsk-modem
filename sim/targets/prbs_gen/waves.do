
set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj prbs_gen_tb
add wave -group TB sim:/$obj/*
add wave -position end sim:/$obj/gen_out/*

# DUT
set obj prbs_gen_tb/dut
add wave -group DUT sim:/$obj/*

configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100