`timescale 1ps/1ps
module cic_filter_tb ();

import bpsk_modem_pkg::*;
import bpsk_tx_pkg::*;
import tb_pkg::*;

// Simulation parameters
parameter   CLK_PERIOD = 10;
parameter   DATA_WIDTH = 8;
parameter   STAGES     = 4;
parameter   UPSAMPLING = 20;
parameter   DIFF_DELAY = 1;
parameter OUTPUT_WIDTH = DATA_WIDTH + STAGES * $clog2(UPSAMPLING * DIFF_DELAY);

// Interfaces
axis_if #(.DATA_WIDTH(CIC_DATA_WIDTH), .FRACT_WIDTH(CIC_FRACT_WIDTH)) cic_in();
axis_if #(.DATA_WIDTH(DUC_DATA_WIDTH), .FRACT_WIDTH(DUC_FRACT_WIDTH)) cic_out();

pulse_driver #(CIC_DATA_WIDTH, CIC_FRACT_WIDTH) drv_a = new(cic_in);

bit clk, rst;
always #(CLK_PERIOD/2) clk = ~clk;

cic_filter #(
    .DECIMATE(0),
    .UPSAMPLING(CIC_R),
    .STAGES(CIC_N),
    .DIFF_DELAY(CIC_D)
) dut (
    .clk(clk),
    .rst(rst),

    .s_axis(cic_in),
    .m_axis(cic_out)
);

initial begin
clk <= 0;
rst <= 1;
cic_in.valid <= 0;
cic_in.data <= 0;
#(3*CLK_PERIOD);
rst <= 0;
@(posedge clk);
drv_a.apply_pulse_from_file (clk, "../test_data_up.txt", 20, 0);
$stop;
end

endmodule
