set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj modem_tx_tb
add wave -group TB sim:/$obj/*

# DUT
set obj modem_tx_tb/dut
add wave -group DUT sim:/$obj/*
add wave -group PRBS_IF sim:/$obj/prbs_if/*
add wave -group FRAMER_IF sim:/$obj/framer_if/*

# FRAMER
set obj modem_tx_tb/dut/framer_inst
add wave -group FRAMER sim:/$obj/*

# run 500ns

configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100