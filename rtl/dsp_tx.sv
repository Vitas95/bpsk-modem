module dsp_tx(
    input logic clk,
    input logic rst,

    axis_if.slave s_axis,
    axis_if.master m_axis
);

import bpsk_modem_pkg::*;
import bpsk_tx_pkg::*;

axis_if #(.DATA_WIDTH(FIR_DATA_WIDTH), .FRACT_WIDTH(FIR_FRACT_WIDTH)) fir_if(); // upsampler -> fir
axis_if #(.DATA_WIDTH(CIC_DATA_WIDTH), .FRACT_WIDTH(CIC_FRACT_WIDTH)) cic_if(); // fir -> cic
axis_if #(.DATA_WIDTH(DUC_DATA_WIDTH), .FRACT_WIDTH(DUC_FRACT_WIDTH)) duc_if(); // cic -> duc

upsampler #(
	.CLK_FREQ(80_000_000),  
    .IN_SAMPLE_RATE(1_000_000),
    .OUT_SAMPLE_RATE(4_000_000),
	.HOLD(0)
) upsampler_inst (
	.clk(clk),
	.rst(rst),

    .s_axis(s_axis),
    .m_axis(fir_if)
);

// Pulse shaping with a FIR filter
mac_fir #(
    .COEFF_WIDTH(FIR_COEFF_WIDTH),
    .COEFF_NUM(FIR_COEFF_NUM)
) mac_fir_inst (
    .clk(clk),
    .rst(rst),

    .s_axis(fir_if),
    .m_axis(cic_if)
);

// Upsampling to DAC sample rate and anti imaging filtration
cic_filter #(
    .DECIMATE(0),
    .UPSAMPLING(CIC_R),
    .STAGES(CIC_N),
    .DIFF_DELAY(CIC_D)
) up_cic_filter_inst (
    .clk(clk),
    .rst(rst),

    .s_axis(cic_if),
    .m_axis(duc_if)
);

// Digital up conversion (bypassed)
axis_fp_cast #(
    .REGISTERED(1)
) duc_bypass_inst (
    .clk(clk),
    .rst(rst),
 
    .s_axis(duc_if),
    .m_axis(m_axis)
);

endmodule