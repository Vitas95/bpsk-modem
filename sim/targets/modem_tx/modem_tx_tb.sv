`timescale 1ps/1ps

module modem_tx_tb ();

parameter   CLK_PERIOD = 10;

bit clk, rst, tx_en, packet_start;
always #(CLK_PERIOD/2) clk = ~clk;

logic [7:0] header = 16;

import bpsk_tx_pkg::*;

axis_if #(.DATA_WIDTH(2), .HAS_READY(0)) tx_data_if();
axis_if #(.DATA_WIDTH(1), .HAS_READY(1)) rx_data_if();
tx_ctrl_t tx_ctrl;

modem_tx dut (
    .clk(clk),
    .rst(rst),

    .tx_signal(tx_data_if),
    .tx_data(rx_data_if),

    .tx_ctrl(tx_ctrl)
);

initial begin
    clk <= 0;
    rst <= 1;
    #(4*CLK_PERIOD);
    rst <= 0;
    @(posedge clk);
    tx_ctrl.bist_start <= 1;
    #(CLK_PERIOD);
    @(posedge clk);
    tx_ctrl.bist_start <= 0;
end

endmodule