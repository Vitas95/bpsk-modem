`include "axis_checks.svh"
module dagc (
    input logic clk,
    input logic rst,
    
    axis_if.slave  s_axis,
    axis_if.slave  s_axis_mag,
    axis_if.master m_axis,

    output logic locked
);

`CHECK_COMPLEX_FIELD(s_axis, 1)
`CHECK_COMPLEX_FIELD(m_axis, 1)

axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14))    error();           // magnitude_error -> pi_controller
axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14))    error_filtered();  // pi_controller -> agc_amplifier

magnitude_error #(
    .STAGES(14)
) magnitude_error_inst (
    .clk(clk),
    .rst(rst),

    .s_axis(s_axis_mag),
    .m_axis(error) 
);

// PI filter perform a basic filtration of the input error into a 
// control signal with a next few formulas:
// integral     = integral + Ki * error
// proportional = Kp * error
// filter_out   = proportional + integral

localparam COEFF_WIDTH = 16;
localparam logic [COEFF_WIDTH-1:0] Ki = $floor(0.09 * 2**(COEFF_WIDTH-1));
localparam logic [COEFF_WIDTH-1:0] Kp = $floor(0.01 * 2**(COEFF_WIDTH-1));
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
    .UNLOCK_THOLD(1200),
    .UNLOCK_CNT(8),
    .LOCK_THOLD(1100),
    .LOCK_CNT(4)
) lock_detector_inst (
    .clk(clk),
    .rst(rst),
    .s_axis_error(error),
    .locked(locked)
);

amplifier amplifier_inst (
    .clk(clk),
    .rst(rst),

    .s_axis(s_axis),
    .gain(error_filtered),
    .m_axis(m_axis) 
);

endmodule 