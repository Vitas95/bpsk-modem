`timescale 1ps/1ps
module dagc_tb ();

import tb_pkg::*;

tb_clk_if sys();
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(1)) data_in();
axis_if #(.DATA_WIDTH(18), .FRACT_WIDTH(14))              mag_out(); // estimated magnitude
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14))              phase_out(); // estimated phase
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(1)) data_out();

dagc dut (
    .clk(sys.clk),
    .rst(sys.rst),

    .s_axis(data_in),
    .s_axis_mag(mag_out),
    .m_axis(data_out)
);

mag_phase_estimator #(
    .PHASE_WIDTH(16),
    .STAGES(14)
) mag_phase_estimator_inst (
    .clk(sys.clk),
    .rst(sys.rst),

    .s_axis(data_out),
    .m_axis_phase(phase_out),
    .m_axis_mag(mag_out)
);

axis_env #(16, 14, 1, 16, 14, 1) env = new(sys, data_in, data_out);

initial env.run("../est_test_data.txt", 40);

endmodule
