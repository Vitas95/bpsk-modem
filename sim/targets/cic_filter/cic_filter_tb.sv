`timescale 1ps/1ps
module cic_filter_tb ();

import bpsk_modem_pkg::*;
import bpsk_tx_pkg::*;
import tb_pkg::*;
import cic_filter_model_pkg::*;

axis_if #(.DATA_WIDTH(CIC_DATA_WIDTH), .FRACT_WIDTH(CIC_FRACT_WIDTH)) cic_in();
axis_if #(.DATA_WIDTH(DUC_DATA_WIDTH), .FRACT_WIDTH(DUC_FRACT_WIDTH)) cic_out();

tb_clk_if sys();

cic_filter #(
    .DECIMATE(0),
    .UPSAMPLING(CIC_R),
    .STAGES(CIC_N),
    .DIFF_DELAY(CIC_D)
) dut (
    .clk(sys.clk),
    .rst(sys.rst),

    .s_axis(cic_in),
    .m_axis(cic_out)
);

cic_model #(CIC_DATA_WIDTH, CIC_FRACT_WIDTH, DUC_DATA_WIDTH, DUC_FRACT_WIDTH,
            CIC_R, CIC_N, CIC_D, 0) model = new();
axis_env #(CIC_DATA_WIDTH, CIC_FRACT_WIDTH, 0, DUC_DATA_WIDTH, DUC_FRACT_WIDTH, 0) env = new(sys, cic_in, cic_out, model);

initial begin
    env.fixed_drain = 300;   // the interpolator output is valid on every clock, it never goes quiet
    env.run("../test_data_up.txt", 20);
end

endmodule
