set WildcardFilter [lsearch -not -all -inline $WildcardFilter Memory]

# TB
set obj modem_core_tb
add wave -group TB sim:/$obj/*
# add wave -position end -group DATA_OUT sim:/$obj/data_out/*
# add wave -position end -group DATA_IN sim:/$obj/data_in/*

# DUT
set obj modem_core_tb/dut
add wave -group DUT sim:/$obj/*

# MODEM CONTROL
set obj modem_core_tb/dut/modem_control_inst
add wave -group MODEM_CONTROL sim:/$obj/*

# MODEM TX
set obj modem_core_tb/dut/modem_tx_inst
add wave -group MODEM_TX sim:/$obj/*
add wave -group MODEM_TX sim:/$obj/tx_control_inst/*
add wave -group MODEM_TX_PRBS sim:/$obj/prbs_gen_inst/*
add wave -group MODEM_TX_FRAMER sim:/$obj/framer_inst/*

# DSP_IF
set obj modem_core_tb/dut
add wave -group DSP_IF_TX sim:/$obj/dsp_tx_inst/*
add wave -group DSP_IF_TX sim:/$obj/dsp_tx_inst/fir_if/*
add wave -group DSP_IF_TX sim:/$obj/dsp_tx_inst/cic_if/*
add wave -group DSP_IF_TX sim:/$obj/dsp_tx_inst/duc_if/*
add wave -group DSP_IF_TX sim:/$obj/dsp_tx_inst/m_axis/*
add wave -group DSP_IF_RX sim:/$obj/dsp_rx_inst/ddc_if/*
add wave -group DSP_IF_RX sim:/$obj/dsp_rx_inst/cic_if/*
add wave -group DSP_IF_RX sim:/$obj/dsp_rx_inst/fir_if/*

# CIC 
set obj modem_core_tb/dut/dsp_tx_inst/up_cic_filter_inst/g_interpolator
add wave -group CIC sim:/$obj/*
add wave -group CIC sim:/$obj/int_gen[0]/u_int/*

# MODEM RX
set obj modem_core_tb/dut/modem_rx_inst
add wave -group MODEM_RX sim:/$obj/*
add wave -group MODEM_RX sim:/$obj/rx_control_inst/*
add wave -group MODEM_RX_PRBS sim:/$obj/prbs_gen_inst/*
add wave -group MODEM_RX_DEFRAMER sim:/$obj/deframer_inst/*


configure wave -signalnamewidth 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 100