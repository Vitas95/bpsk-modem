`timescale 1ps/1ps
module prbs_gen_tb();

parameter   CLK_PERIOD = 12.5;   // 80 MHz clock

bit clk, rst;
always #(CLK_PERIOD/2) clk = ~clk;

axis_if #(.DATA_WIDTH(1), .FRACT_WIDTH(0), .HAS_READY(1)) gen_out();

prbs_gen #(
	.SEED(1)//.SEED(184)
) dut (
    .clk(clk),
    .rst(rst),
    .gen_out(gen_out)
);

always @(negedge gen_out.last) begin
    gen_out.ready <= 0;
end

initial begin
    clk <= 0;
    rst <= 1;
    gen_out.ready <= 0;
    #(4*CLK_PERIOD);
    rst <= 0;
    @(posedge clk);
    gen_out.ready <= 1;
    #(32*CLK_PERIOD);
    gen_out.ready <= 0;
    @(posedge clk);
    #(4*CLK_PERIOD);
end

endmodule