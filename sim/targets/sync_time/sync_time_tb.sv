`timescale 1ps/1ps
module sync_time_tb ();

import tb_pkg::*;

tb_clk_if sys();
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(1)) data_in();
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(1)) data_out();

sync_time dut (
    .clk(sys.clk),
    .rst(sys.rst),

    .s_axis(data_in),
    .m_axis(data_out)
);

axis_env #(16, 14, 1, 16, 14, 1) env = new(sys, data_in, data_out);

initial env.run("../farrow_test_data.txt", 20);

endmodule
