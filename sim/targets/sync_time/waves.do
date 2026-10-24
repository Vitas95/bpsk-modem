set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj sync_time_tb
add wave -group TB sim:/$obj/sys/*
add wave -group TB sim:/$obj/data_in/*
add wave -group TB sim:/$obj/data_out/*

# DUT
set obj sync_time_tb/dut
add wave -group DUT sim:/$obj/*
add wave -group DUT sim:/$obj/error/*
add wave -group DUT sim:/$obj/error_filtered/*
add wave -group DUT sim:/$obj/data_filtered/*
add wave -group DUT sim:/$obj/m_axis/*


# LOCK_DETECT
set obj sync_time_tb/dut/lock_detector_inst
add wave -group LOCK_DETECT sim:/$obj/*

# FARROW
set obj sync_time_tb/dut/farrow_filter_inst/farrow_filter_i
add wave -group FARROW sim:/$obj/*

# GARDNER
set obj sync_time_tb/dut/gardner_error_inst
add wave -group GARDNER sim:/$obj/*

# PI
set obj sync_time_tb/dut/pi_controller_inst
add wave -group PI sim:/$obj/*

configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100