`include "axis_checks.svh"
module fir_cplx_wrap #(
    parameter COEFF_WIDTH,
    parameter COEFF_NUM
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

mac_fir #(
    .COEFF_WIDTH(COEFF_WIDTH),
    .COEFF_NUM(COEFF_NUM)
) mac_fir_inst_i (
    .clk(clk),
    .rst(rst),

    .s_axis(s_axis_i),
    .m_axis(m_axis_i)
);

mac_fir #(
    .COEFF_WIDTH(COEFF_WIDTH),
    .COEFF_NUM(COEFF_NUM)
) mac_fir_inst_q (
    .clk(clk),
    .rst(rst),

    .s_axis(s_axis_q),
    .m_axis(m_axis_q)
);

assign m_axis.data  = {m_axis_q.data, m_axis_i.data};
assign m_axis.valid = m_axis_i.valid;

endmodule