set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj mag_phase_estimator_tb
add wave -group TB sim:/$obj/sys/*
add wave -group TB sim:/$obj/data_in/*
add wave -group TB sim:/$obj/phase_out/*
add wave -group TB sim:/$obj/mag_out/*

# DUT
set obj mag_phase_estimator_tb/dut
add wave -group DUT sim:/$obj/*

# CORDIC
set obj mag_phase_estimator_tb/dut/cordic_inst
add wave -group CORDIC sim:/$obj/*
add wave -group CORDIC sim:/$obj/CORDIC_iter/*

configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100