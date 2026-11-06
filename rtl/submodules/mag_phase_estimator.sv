`include "axis_checks.svh"
module mag_phase_estimator #(
    parameter PHASE_WIDTH,
    parameter STAGES
) (
    input logic clk,
    input logic rst,

    axis_if.slave s_axis,
    axis_if.master m_axis_phase,
    axis_if.master m_axis_mag
);

`CHECK_COMPLEX_FIELD(s_axis, 1)

localparam DATA_WIDTH = s_axis.DATA_WIDTH;

logic signed [DATA_WIDTH-1:0]  data_real, data_imag;
logic        [DATA_WIDTH+1:0]    mag;
logic        [PHASE_WIDTH-1:0] phase;
logic                          valid_out;

assign data_real = s_axis.data[DATA_WIDTH-1:0];
assign data_imag = s_axis.data[DATA_WIDTH*2-1:DATA_WIDTH];

cordic #(
    .STAGES(STAGES),
    .DATA_WIDTH(DATA_WIDTH),
    .PHASE_WIDTH(PHASE_WIDTH),
    .PIPLINED(0),
    .ROTATIONAL(0)
) cordic_inst (
    .clk(clk),
    .rst(rst),

    .X_in(data_real),
    .Y_in(data_imag),
    .X_out(mag),
    .valid(valid_out),
    .error(phase),
    .phase_in(16'd0),
    .phase_valid_in(s_axis.valid)
);

assign m_axis_phase.data  = phase;
assign m_axis_phase.valid = valid_out;
assign m_axis_mag.data    = mag;
assign m_axis_mag.valid   = valid_out;

endmodule