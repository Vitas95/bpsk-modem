`timescale 1ps/1ps
module farrow_filter_tb ();

import tb_pkg::*;
import farrow_filter_model::*;

parameter DELAY_WIDTH = 16;
localparam DELAY = 256; // Some dalay calculated with an error loop.

tb_clk_if sys();
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(1)) data_in();
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(1)) data_out();

logic [DELAY_WIDTH-1:0] delay_in;
assign delay_in = DELAY;

farrow_cplx_wrap #(
    .DELAY_WIDTH(DELAY_WIDTH)
) dut (
    .clk(sys.clk),
    .rst(sys.rst),

    .s_axis(data_in),
    .delay_in(delay_in),
    .correction_en_in(1'b1),
    .m_axis(data_out)
);

farrow_model #(16, 1, DELAY_WIDTH) model = new(DELAY, 1);   // (delay_in, correction_en_in)
axis_env #(16, 14, 1, 16, 14, 1) env = new(sys, data_in, data_out, model);

initial env.run("../farrow_test_data.txt", 20);

endmodule
