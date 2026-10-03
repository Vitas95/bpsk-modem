//////////////////////////////////////////////////////////////////////////////////
// Module: dsp_bypass
// Description:
//   Placeholder for the future DSP chain; a temporary solution 
//   for verifying loopback logic in the modem core.
//////////////////////////////////////////////////////////////////////////////////

module dsp_bypass #(
    parameter REGISTERED = 1
) (
    input  logic clk,
    input  logic rst,

    axis_if.slave  s_axis, 
    axis_if.master m_axis 
);

axis_fp_cast #(
    .REGISTERED(REGISTERED)
) axis_fp_cast_inst (
    .clk(clk),
    .rst(rst),
 
    .s_axis(s_axis),
    .m_axis(m_axis)
);

endmodule