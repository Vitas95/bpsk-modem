`timescale 1ps/1ps
module digital_converter_tb ();

import tb_pkg::*;


axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(1)) dc_in();
axis_if #(.DATA_WIDTH(8), .FRACT_WIDTH(6)) ADC_to_DAC();
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(1)) dc_out();

tb_clk_if sys();

digital_converter #(
    .EXP_WIDTH(15),
    .PHASE_WIDTH(16),
    .DOWN_CONVERSION(0)
) dut_0 (
    .clk(sys.clk),
    .rst(sys.rst),

    .s_axis(dc_in),
    .m_axis(ADC_to_DAC)
);

digital_converter #(
    .EXP_WIDTH(15),
    .PHASE_WIDTH(16),
    .DOWN_CONVERSION(1)
) dut_1 (
    .clk(sys.clk),
    .rst(sys.rst),

    .s_axis(ADC_to_DAC),
    .m_axis(dc_out)
);

axis_env #(16, 14, 1, 16, 14, 1) env = new(sys, dc_in, dc_out);

initial begin
    env.run("../digital_converter_up_test.txt", 1);
end

endmodule
