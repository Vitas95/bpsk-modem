set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj mapper_tb
add wave -group TB sim:/$obj/*
add wave -position end -group DATA_OUT sim:/$obj/data_out/*
add wave -position end -group DATA_IN sim:/$obj/data_in/*

# DUT
set obj mapper_tb/dut
add wave -group DUT sim:/$obj/*

configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100