set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj dapc_tb
add wave -group TB sim:/$obj/sys/*
add wave -group TB sim:/$obj/data_in/*
add wave -group TB sim:/$obj/data_out/*

# DUT
set obj dapc_tb/dut
add wave -group DUT sim:/$obj/*
# add wave -group DUT sim:/$obj/s_axis_phase/*
add wave -group DUT sim:/$obj/error/*
add wave -group DUT sim:/$obj/error_filtered/*
add wave -group DUT sim:/$obj/m_axis/*

# LOCK_DETECT
set obj dapc_tb/dut/lock_detector_inst
add wave -group LOCK_DETECT sim:/$obj/*

# PI
set obj dapc_tb/dut/pi_controller_inst
add wave -group PI sim:/$obj/*

# COMP
set obj dapc_tb/dut/phase_comp_inst
add wave -group COMP sim:/$obj/*
add wave -group COMP sim:/$obj/exp/*

# EXP
set obj dapc_tb/dut/phase_comp_inst/exp_lut_inst
add wave -group EXP sim:/$obj/*

configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100