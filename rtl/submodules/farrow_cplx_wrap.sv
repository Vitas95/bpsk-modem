`include "axis_checks.svh"
module farrow_cplx_wrap #(
    parameter DELAY_WIDTH   = 16
) (
    input logic clk,
    input logic rst,

    axis_if.slave s_axis,
    axis_if.master m_axis,

    input logic [DELAY_WIDTH-1:0] delay_in,
    input logic                   correction_en_in
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

farrow_filter #(
    .DELAY_WIDTH(DELAY_WIDTH)
) farrow_filter_i (
    .clk             (clk),
    .rst             (rst),
    .s_axis          (s_axis_i),
    .m_axis          (m_axis_i),
    .delay_in        (delay_in),
    .correction_en_in(correction_en_in)
);

farrow_filter #(
    .DELAY_WIDTH(DELAY_WIDTH)
) farrow_filter_q (
    .clk             (clk),
    .rst             (rst),
    .s_axis          (s_axis_q),
    .m_axis          (m_axis_q),
    .delay_in        (delay_in),
    .correction_en_in(correction_en_in)
);

assign m_axis.data  = {m_axis_q.data, m_axis_i.data};
assign m_axis.valid = m_axis_i.valid;

endmodule