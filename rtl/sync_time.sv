`include "axis_checks.svh"
module sync_time (
    input logic clk,
    input logic rst,

    axis_if.slave s_axis,
    axis_if.master m_axis
);

`CHECK_COMPLEX_FIELD(s_axis, 1)
`CHECK_COMPLEX_FIELD(m_axis, 1)

axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14))             error();           // gardner_error -> pi_controller
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14))             error_filtered();  // pi_controller -> farrow_filter
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(1)) data_filtered();   // farrow_filter -> gardner_error

gardner_error gardner_error_inst (
    .clk(clk),
    .rst(rst),

    .s_axis(data_filtered),
    .m_axis_data(m_axis),
    .m_axis_error(error) 
);

pi_controller pi_controller_inst (
    .clk(clk),
    .rst(rst),

    .s_axis(error),
    .m_axis(error_filtered)
);

farrow_cplx_wrap #(
    .DELAY_WIDTH(16)
) farrow_filter_inst (
    .clk(clk),
    .rst(rst),

    .s_axis(s_axis),
    .delay_in(error_filtered.data),
    .correction_en_in(1'b1),
    .m_axis(data_filtered)
);



endmodule