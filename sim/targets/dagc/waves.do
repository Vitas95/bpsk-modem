set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj dagc_tb
add wave -group TB sim:/$obj/sys/*
add wave -group TB sim:/$obj/data_in/*
add wave -group TB sim:/$obj/data_out/*

# DUT
set obj dagc_tb/dut
add wave -group DUT sim:/$obj/*
add wave -group DUT sim:/$obj/error/*
add wave -group DUT sim:/$obj/error_filtered/*
add wave -group DUT sim:/$obj/m_axis/*

# LOCK_DETECT
set obj dagc_tb/dut/lock_detector_inst
add wave -group LOCK_DETECT sim:/$obj/*

# PI
set obj dagc_tb/dut/pi_controller_inst
add wave -group PI sim:/$obj/*

configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100