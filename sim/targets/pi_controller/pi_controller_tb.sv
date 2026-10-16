`timescale 1ps/1ps
`include "pi_controller_model.sv"

module pi_controller_tb ();

import tb_pkg::*;

// Simulation parameters
parameter   CLK_PERIOD = 10;
localparam  DATA_WIDTH  = 16;
localparam  FRACT_WIDTH = 14;

axis_if #(.DATA_WIDTH(DATA_WIDTH), .FRACT_WIDTH(FRACT_WIDTH)) data_in();
axis_if #(.DATA_WIDTH(DATA_WIDTH), .FRACT_WIDTH(FRACT_WIDTH)) data_out();

pulse_driver #(DATA_WIDTH, FRACT_WIDTH) drv_a = new(data_in);

shortreal error_flp, i_state;

bit clk, rst;
always #(CLK_PERIOD/2) clk = ~clk;

pi_controller dut (
    .clk(clk),
    .rst(rst),

    .s_axis(data_in),
    .m_axis(data_out)
);

always @(posedge clk) begin
    if (data_out.valid) begin
        error_flp = calculate_pi (data_in.data, $floor(0.005 * 2**(15)), $floor(0.0005 * 2**(15)), i_state, i_state);
        $display("Time: %0t | Controller output: %h", $time, error_flp);
    end
end

initial begin
clk <= 0;
rst <= 1;
data_in.valid <= 0;
data_in.data <= 0;
#(3*CLK_PERIOD);
rst <= 0;
@(posedge clk);
drv_a.apply_pulse_from_file (clk, "../loop_test_data.txt", 40, 0);
$stop;
end

endmodule
