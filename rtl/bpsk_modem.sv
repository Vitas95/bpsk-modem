//////////////////////////////////////////////////////////////////////////////////
// Module: bpsk_modem
// Description:
//   Top wrapper of the modem. It will combine register space with the modem
//   core in the future.
//
//
//////////////////////////////////////////////////////////////////////////////////

module bpsk_modem 
    import bpsk_modem_pkg::*;
(
    parameter ADC_DATA_WIDTH = ADC_DATA_WIDTH,
    parameter DAC_DATA_WIDTH = DAC_DATA_WIDTH,
    parameter DATA_WIDTH     = DATA_WIDTH
) (
    input clk,
    input rst,

    // ADC interface 
    input logic  [ADC_DATA_WIDTH-1:0] s_axis_adc_tdata,
    input logic                       s_axis_adc_tvalid,
    
    // DAC interface
    output logic [DAC_DATA_WIDTH-1:0] m_axis_dac_tdata,
    output logic                      m_axis_dac_tvalid

    // Transmit data port
    input logic  [DATA_WIDTH-1:0] s_axis_tx_tdata,
    input logic                   s_axis_tx_tvalid,

    // Received data port
    input logic  [DATA_WIDTH-1:0] s_axis_rx_tdata,
    input logic                   s_axis_rx_tvalid,
);

axis_if #(.DATA_WIDTH(ADC_DATA_WIDTH), .FRACT_WIDTH(0)) adc_if();
assign adc_if.data  = s_axis_adc_tdata;
assign adc_if.valid = s_axis_adc_tvalid;

axis_if #(.DATA_WIDTH(DAC_DATA_WIDTH), .FRACT_WIDTH(0)) dac_if();
assign dac_if.data  = s_axis_dac_tdata;
assign dac_if.valid = s_axis_dac_tvalid;

axis_if #(.DATA_WIDTH(DATA_WIDTH), .FRACT_WIDTH(0), .READY(1)) tx_if();
// assign tx_if.data  = s_axis_tx_tdata;
// assign tx_if.valid = s_axis_tx_tvalid;
assign tx_if.data  = '0;
assign tx_if.valid = 0;

axis_if #(.DATA_WIDTH(DATA_WIDTH), .FRACT_WIDTH(0),) rx_if();
assign rx_if.data  = s_axis_rx_tdata;
assign rx_if.valid = s_axis_rx_tvalid;

modem_core modem_core_inst(
    .clk(clk),
    .rst(rst),

    .adc_in_if(adc_if.slave),
    .dac_out_if(dac_if.master),

    .tx_data_in(tx_if.slave),
    .rx_data_out(rx_if.master)
);

endmodule