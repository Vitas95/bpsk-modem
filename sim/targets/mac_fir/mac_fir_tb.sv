`timescale 1ps/1ps
module mac_fir_tb ();

import bpsk_modem_pkg::*;
import bpsk_tx_pkg::*;
import tb_pkg::*;

// Simulation parameters
parameter   CLK_PERIOD = 10;

axis_if #(.DATA_WIDTH(FIR_DATA_WIDTH), .FRACT_WIDTH(FIR_FRACT_WIDTH)) fir_in();
axis_if #(.DATA_WIDTH(CIC_DATA_WIDTH), .FRACT_WIDTH(CIC_FRACT_WIDTH)) fir_out();

pulse_driver #(FIR_DATA_WIDTH, FIR_FRACT_WIDTH) drv_a = new(fir_in);

bit clk, rst;
always #(CLK_PERIOD/2) clk = ~clk;

mac_fir #(
    .COEFF_WIDTH(FIR_COEFF_WIDTH),
    .COEFF_NUM(FIR_COEFF_NUM)
) dut (
    .clk(clk),
    .rst(rst),

    .s_axis(fir_in),
    .m_axis(fir_out)
);

initial begin
clk <= 0;
rst <= 1;
fir_in.data <= 0;
fir_in.valid <= 0;
#(3*CLK_PERIOD);
rst <= 0;
@(posedge clk);
drv_a.apply_pulse_from_file (clk, "../test_data.txt", 20, 0);
$stop;
end

endmodule
