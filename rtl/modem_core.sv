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

axis_if #(.DATA_WIDTH(2)) tx_signal();
axis_if #(.DATA_WIDTH(2)) rx_signal();

///////////////////////////
// Mainblock connections //
///////////////////////////

tx_ctrl_t tx_ctrl;
tx_status_t tx_status;
rx_ctrl_t rx_ctrl;
rx_status_t rx_status;

modem_tx modem_tx_inst(
    .clk(clk),
    .rst(rst),

    .tx_signal(tx_signal),  
    .tx_data(tx_data_in),  

    .tx_ctrl(tx_ctrl),
    .tx_status(tx_status)
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
    .digital_loopback(digital_loopback),

    .modem_ctrl(modem_ctrl),   
    .modem_status(modem_status)
);

//////////////////////
// Digital loopback //
//////////////////////

always_comb begin
    if (digital_loopback) begin
        rx_signal.data  = tx_signal.data;
        rx_signal.valid = tx_signal.valid;

        dac_out_if.data  = '0;
        dac_out_if.valid =  0;
    end else begin
        rx_signal.data  = adc_in_if.data;
        rx_signal.valid = adc_in_if.valid;

        dac_out_if.data  = tx_signal.data;
        dac_out_if.valid = tx_signal.valid;
    end
end

endmodule