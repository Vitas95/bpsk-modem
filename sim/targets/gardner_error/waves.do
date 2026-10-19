set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj gardner_error_tb
add wave -group TB sim:/$obj/sys/*
add wave -group TB sim:/$obj/data_in/*
add wave -group TB sim:/$obj/data_out/*
add wave -group TB sim:/$obj/error_out/*

# DUT
set obj gardner_error_tb/dut
add wave -group DUT sim:/$obj/*


configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100