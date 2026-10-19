`timescale 1ps/1ps
module mac_fir_tb ();

import bpsk_modem_pkg::*;
import bpsk_tx_pkg::*;
import tb_pkg::*;
import mac_fir_model_pkg::*;

tb_clk_if sys();
axis_if #(.DATA_WIDTH(FIR_DATA_WIDTH), .FRACT_WIDTH(FIR_FRACT_WIDTH)) fir_in();
axis_if #(.DATA_WIDTH(CIC_DATA_WIDTH), .FRACT_WIDTH(CIC_FRACT_WIDTH)) fir_out();

mac_fir #(
    .COEFF_WIDTH(FIR_COEFF_WIDTH),
    .COEFF_NUM(FIR_COEFF_NUM)
) dut (
    .clk(sys.clk),
    .rst(sys.rst),

    .s_axis(fir_in),
    .m_axis(fir_out)
);

mac_fir_model #(FIR_DATA_WIDTH, FIR_FRACT_WIDTH, CIC_DATA_WIDTH, CIC_FRACT_WIDTH) model = new();
axis_env #(FIR_DATA_WIDTH, FIR_FRACT_WIDTH, 0, CIC_DATA_WIDTH, CIC_FRACT_WIDTH, 0) env = new(sys, fir_in, fir_out, model);

initial env.run("../test_data.txt", 20);   // the FIR needs >= 12 clocks per sample

endmodule
