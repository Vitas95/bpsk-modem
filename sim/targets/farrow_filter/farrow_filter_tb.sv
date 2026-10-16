`timescale 1ps/1ps
module farrow_filter_tb ();

import tb_pkg::*;

// Simulation parameters
parameter   CLK_PERIOD = 10; 
parameter   DELAY_WIDTH = 16;

axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(0)) data_in();
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(0)) data_out();

pulse_driver #(16, 14, 0) drv_a = new(data_in);

bit clk, rst;
always #(CLK_PERIOD/2) clk = ~clk;

logic [DELAY_WIDTH-1:0] delay_in;
assign delay_in = 16384+256; // Unsigned 0.5 with some dalay calculated with an error loop.

farrow_filter #(
    .DELAY_WIDTH(DELAY_WIDTH)
) dut (
    .clk(clk),
    .rst(rst),

    .s_axis(data_in),
    .delay_in(delay_in),
    .correction_en_in(1'b1),
    .m_axis(data_out)
);

initial begin
clk <= 0;
rst <= 1;
data_in.valid <= 0;
data_in.data <= 0;
#(3*CLK_PERIOD);
rst <= 0;
@(posedge clk);
drv_a.apply_pulse_from_file (clk, "../test_data.txt", 20, 0);
$stop;
end

endmodule
