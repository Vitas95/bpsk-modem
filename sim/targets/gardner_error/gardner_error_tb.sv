`timescale 1ps/1ps
module gardner_error_tb ();

import tb_pkg::*;
import gardner_model::*;

localparam WIDTH  = 16;
localparam FRACTIONAL = 14;

tb_clk_if sys();
axis_if #(.DATA_WIDTH(WIDTH), .FRACT_WIDTH(FRACTIONAL), .COMPLEX(1)) data_in();
axis_if #(.DATA_WIDTH(WIDTH), .FRACT_WIDTH(FRACTIONAL), .COMPLEX(1)) data_out();
axis_if #(.DATA_WIDTH(WIDTH), .FRACT_WIDTH(FRACTIONAL)) error_out();

gardner_error dut (
    .clk(sys.clk),
    .rst(sys.rst),

    .s_axis(data_in),
    .m_axis_data(data_out),
    .m_axis_error(error_out)
);

gardner_model #(.OUT_SHIFT(FRACTIONAL)) model = new();
axis_env #(WIDTH, FRACTIONAL, 1, WIDTH, FRACTIONAL, 0) env = new(sys, data_in, error_out, model);

initial env.run("../gardner_test_data.txt", 20);

endmodule