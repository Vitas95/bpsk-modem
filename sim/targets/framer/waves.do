set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj framer_tb
add wave -group TB sim:/$obj/*
add wave -position end -group TB_DATA_IN sim:/$obj/data_in/*
add wave -position end -group TB_PRBS_IN sim:/$obj/prbs_in/*
add wave -position end -group TB_DATA_OUT sim:/$obj/data_out/*

# DUT
set obj framer_tb/dut
add wave -group DUT sim:/$obj/*

configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100