`include "axis_checks.svh"
module sync_time (
    input logic clk,
    input logic rst,

    axis_if.slave s_axis,
    axis_if.master m_axis,

    output logic locked
);

`CHECK_COMPLEX_FIELD(s_axis, 1)
`CHECK_COMPLEX_FIELD(m_axis, 1)

axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14))              error();           // gardner_error -> pi_controller
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14))              error_filtered();  // pi_controller -> farrow_filter
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(1)) data_filtered();   // farrow_filter -> gardner_error

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

gardner_error gardner_error_inst (
    .clk(clk),
    .rst(rst),

    .s_axis(data_filtered),
    .m_axis_data(m_axis),
    .m_axis_error(error) 
);

// PI filter perform a basic filtration of the input error into a 
// control signal with a next few formulas:
// integral     = integral + Ki * error
// proportional = Kp * error
// filter_out   = proportional + integral

localparam COEFF_WIDTH = 16;
localparam logic [COEFF_WIDTH-1:0] Ki = $floor(0.0002* 2**(COEFF_WIDTH-1));
localparam logic [COEFF_WIDTH-1:0] Kp = $floor(0.008 * 2**(COEFF_WIDTH-1));

pi_controller #(
    .COEFF_WIDTH(COEFF_WIDTH)
) pi_controller_inst (
    .clk(clk),
    .rst(rst),

    .Ki(Ki),
    .Kp(Kp),

    .s_axis(error),
    .m_axis(error_filtered)
);

lock_detector #(
    .UNLOCK_THOLD(32),
    .UNLOCK_CNT(16),
    .LOCK_THOLD(16),
    .LOCK_CNT(8)
) lock_detector_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_error(error_filtered),
    .locked(locked)
);

endmodule