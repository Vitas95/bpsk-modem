//////////////////////////////////////////////////////////////////////////////////
// Module: modem_core
// Description:
//   Top-level integration of the BPSK modem: connects modem_tx, modem_rx and
//   modem_control, and inserts two DSP bypass placeholders (dsp_tx/dsp_rx)
//   between the baseband stage and the DAC/ADC interfaces.
//////////////////////////////////////////////////////////////////////////////////
//   tx_data_in                                                           '0
//       │                                                                 |
//       V                                                                 V
//  +----------+  tx_signal             +--------+   tx_dsp          +-----------+ dac_out_if
//  │ modem_tx │-----------------+----->│ dsp_tx │----------+------->│  RF mux   │--------->
//  +----------+                 |      +--------+          |        +-----------+
//                               |                          |               
//                               |                          +---------------+
//                               |                                          |
//                               V                                          V
//                          +----------+                               +----------+
//  +----------+  rx_signal │ Baseband | rx_dsp_out +--------+  rx_dsp |    DSP   | adc_in_if
//  | modem_rx |<-----------│ loopback |<-----------| dsp_rx |<--------| loopback |<--------
//  +----------+            │   mux    |            +--------+         |    mux   │ 
//        |                 +----------+                               +----------+
//        V
//   rx_data_out
//
//////////////////////////////////////////////////////////////////////////////

module modem_core (
    input clk,
    input rst,

    // DAC and ADC interfaces
    axis_if.slave adc_in_if,
    axis_if.master dac_out_if,

    // Input and output data interfaces
    axis_if.slave tx_data_in,
    axis_if.master rx_data_out,

    // Control inputs
    input bpsk_modem_pkg::modem_ctrl_t modem_ctrl,
    
    // Status outputs
    output bpsk_modem_pkg::modem_status_t modem_status
);

import bpsk_modem_pkg::*;
import bpsk_tx_pkg::*;
import bpsk_rx_pkg::*;

axis_if #(.DATA_WIDTH(2))                   tx_signal();      // modem_tx -> dsp_tx
axis_if #(.DATA_WIDTH(2))                   tx_signal_test(); // modem_tx -> dsp_tx_test
axis_if #(.DATA_WIDTH(DAC_ADC_DATA_WIDTH))  tx_dsp();         // dsp_tx -> DAC
axis_if #(.DATA_WIDTH(DAC_ADC_DATA_WIDTH))  tx_dsp_test();    // dsp_tx_test
axis_if #(.DATA_WIDTH(DAC_ADC_DATA_WIDTH))  rx_dsp();         // ADC -> dsp_rx  
axis_if #(.DATA_WIDTH(DAC_ADC_DATA_WIDTH))  rx_dsp_out();     // dsp_rx -> loopback_mux  
axis_if #(.DATA_WIDTH(2))                   rx_signal();      // loopback_mux -> modem_rx

///////////////////////////
// Mainblock connections //
///////////////////////////

tx_ctrl_t tx_ctrl;
tx_status_t tx_status;
rx_ctrl_t rx_ctrl;
rx_status_t rx_status;
modem_mode_e loopback_mode;

modem_tx modem_tx_inst(
    .clk(clk),
    .rst(rst),

    .tx_signal(tx_signal),  
    .tx_data(tx_data_in),  

    .tx_ctrl(tx_ctrl),
    .tx_status(tx_status)
);

dsp_bypass #(
    .REGISTERED(1)
) dsp_tx_bypass (
    .clk(clk),
    .rst(rst),

    .s_axis(tx_signal), 
    .m_axis(tx_dsp) 
);

assign tx_signal_test.data  = tx_signal.data;
assign tx_signal_test.valid = tx_signal.valid;
// DSP tx test
dsp_tx dsp_tx_inst(
    .clk(clk),
    .rst(rst),

    .s_axis(tx_signal_test), 
    .m_axis(tx_dsp_test) 
);

dsp_bypass #(
    .REGISTERED(1)
) dsp_rx_bypass (
    .clk(clk),
    .rst(rst),

    .s_axis(rx_dsp), 
    .m_axis(rx_dsp_out) 
);

modem_rx modem_rx_inst (
    .clk(clk),
    .rst(rst),

    .rx_signal(rx_signal),
    .rx_data(rx_data_out),

    .rx_ctrl(rx_ctrl),
    .rx_status(rx_status)
);

modem_control #(
    .HEADER_LEN(HEADER_LEN),
    .BIST_PKT_CNT(BIST_PKT_CNT)
) modem_control_inst (
    .clk(clk),
    .rst(rst),

    .tx_ctrl(tx_ctrl),
    .tx_status(tx_status),
    
    .rx_ctrl(rx_ctrl),
    .rx_status(rx_status),      

    // Modem core control
    .loopback_mode(loopback_mode),

    .modem_ctrl(modem_ctrl),   
    .modem_status(modem_status)
);

//////////////////////
// Digital loopback //
//////////////////////

always_comb begin
    if (loopback_mode == LOOPBACK_BASEBAND) begin
        rx_signal.data  = tx_signal.data;
        rx_signal.valid = tx_signal.valid;
    end else begin
        rx_signal.data  = rx_dsp_out.data;
        rx_signal.valid = rx_dsp_out.valid;
    end
end

always_comb begin
    if (loopback_mode == LOOPBACK_DSP) begin
        rx_dsp.data  = tx_dsp.data;
        rx_dsp.valid = tx_dsp.valid;
    end else begin
        rx_dsp.data  = adc_in_if.data;
        rx_dsp.valid = adc_in_if.valid;
    end

    // dac_out_if gets signal only in RF mode
    dac_out_if.data  = (loopback_mode == RF) ? tx_dsp.data  :   '0;
    dac_out_if.valid = (loopback_mode == RF) ? tx_dsp.valid : 1'b0;
end

endmodule