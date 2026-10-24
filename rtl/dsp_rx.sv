module dsp_rx(
    input logic clk,
    input logic rst,

    axis_if.slave s_axis,
    axis_if.master m_axis,

    output logic locked
);

import bpsk_modem_pkg::*;
import bpsk_rx_pkg::*;

axis_if #(.DATA_WIDTH(DDC_DATA_WIDTH), .FRACT_WIDTH(DDC_FRACT_WIDTH), .COMPLEX(1)) ddc_if(); // ddc -> cic
axis_if #(.DATA_WIDTH(CIC_DATA_WIDTH), .FRACT_WIDTH(CIC_FRACT_WIDTH), .COMPLEX(1)) cic_if(); // cic -> fir
axis_if #(.DATA_WIDTH(FIR_DATA_WIDTH), .FRACT_WIDTH(FIR_FRACT_WIDTH), .COMPLEX(1)) fir_if(); // fir -> sync

// Digital down conversion
digital_converter #(
    .EXP_WIDTH(15),
    .PHASE_WIDTH(16),
    .DOWN_CONVERSION(1)
) dut_1 (
    .clk(clk),
    .rst(rst),

    .s_axis(s_axis),
    .m_axis(ddc_if)
);

// Downsampling
cic_cplx_wrap #(
    .DECIMATE(1),
    .UPSAMPLING(CIC_R),
    .STAGES(CIC_N),
    .DIFF_DELAY(CIC_D)
) cic_filter_inst (
    .clk(clk),
    .rst(rst),

    .s_axis(ddc_if),
    .m_axis(cic_if)
);

// Pulse shaping with a FIR filter
fir_cplx_wrap #(
    .COEFF_WIDTH(FIR_COEFF_WIDTH),
    .COEFF_NUM(FIR_COEFF_NUM)
) mac_fir_inst (
    .clk(clk),
    .rst(rst),

    .s_axis(cic_if),
    .m_axis(fir_if)
);

// Syncronization (bypassed)
// axis_fp_cast #(
//     .REGISTERED(1)
// ) sync_bypass_inst (
//     .clk(clk),
//     .rst(rst),
 
//     .s_axis(fir_if),
//     .m_axis(m_axis)
// );

sync_time sync_time_inst(
    .clk(clk),
    .rst(rst),

    .s_axis(fir_if),
    .m_axis(m_axis),

    .locked(locked)
);

endmodule