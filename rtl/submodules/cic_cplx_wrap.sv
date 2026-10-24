`include "axis_checks.svh"
module cic_cplx_wrap #(
    parameter UPSAMPLING = 20,
    parameter STAGES = 4,
    parameter DIFF_DELAY = 1,
    parameter DECIMATE = 0  // 0 - interpolation, 1 - decimation
) (
    input logic clk,
    input logic rst,

    axis_if.slave s_axis,
    axis_if.master m_axis
);

`CHECK_COMPLEX_FIELD(s_axis, 1)
`CHECK_COMPLEX_FIELD(m_axis, 1)

localparam DATA_WIDTH = s_axis.DATA_WIDTH;

axis_if #(
    .DATA_WIDTH(DATA_WIDTH),
    .COMPLEX(0)
) s_axis_i (), s_axis_q (), m_axis_i (), m_axis_q ();

assign s_axis_i.data  = s_axis.data[DATA_WIDTH-1:0];
assign s_axis_q.data  = s_axis.data[2*DATA_WIDTH-1:DATA_WIDTH];
assign s_axis_i.valid = s_axis.valid;
assign s_axis_q.valid = s_axis.valid;

cic_filter #(
    .DECIMATE(DECIMATE),
    .UPSAMPLING(UPSAMPLING),
    .STAGES(STAGES),
    .DIFF_DELAY(DIFF_DELAY)
) cic_filter_inst_i (
    .clk(clk),
    .rst(rst),

    .s_axis(s_axis_i),
    .m_axis(m_axis_i)
);

cic_filter #(
    .DECIMATE(DECIMATE),
    .UPSAMPLING(UPSAMPLING),
    .STAGES(STAGES),
    .DIFF_DELAY(DIFF_DELAY)
) cic_filter_inst_q (
    .clk(clk),
    .rst(rst),

    .s_axis(s_axis_q),
    .m_axis(m_axis_q)
);

assign m_axis.data  = {m_axis_q.data, m_axis_i.data};
assign m_axis.valid = m_axis_i.valid;

endmodule