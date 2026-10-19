`timescale 1ps/1ps
module pi_controller_tb ();

import tb_pkg::*;
import pi_controller_model::*;

localparam WIDTH  = 16;
localparam FRACTIONAL = 14;

tb_clk_if sys();
axis_if #(.DATA_WIDTH(WIDTH), .FRACT_WIDTH(FRACTIONAL)) data_in();
axis_if #(.DATA_WIDTH(WIDTH), .FRACT_WIDTH(FRACTIONAL)) data_out();

pi_controller dut (
    .clk(sys.clk),
    .rst(sys.rst),

    .s_axis(data_in),
    .m_axis(data_out)
);

pi_model model = new();
axis_env #(WIDTH, FRACTIONAL, 0, WIDTH, FRACTIONAL, 0) env = new(sys, data_in, data_out, model);

initial env.run("../loop_test_data.txt", 40);

endmodule
