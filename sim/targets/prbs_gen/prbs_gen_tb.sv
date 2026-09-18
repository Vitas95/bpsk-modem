`timescale 1ps/1ps
module prbs_gen_tb();

parameter   CLK_PERIOD = 12.5;   // 80 MHz clock

bit clk, rst;
always #(CLK_PERIOD/2) clk = ~clk;

axis_if #(.DATA_WIDTH(1), .FRACT_WIDTH(0), .HAS_READY(1)) gen_out();
logic seed_valid;
logic [7:0] seed;

prbs_gen dut (
    .clk(clk),
    .rst(rst),

    .seed(seed),
    .seed_valid(seed_valid),
    .gen_out(gen_out)
);

always @(negedge gen_out.last) begin
    gen_out.ready <= 0;
end

task init();
    clk <= 0;
    rst <= 1;
    gen_out.ready <= 0;
    #(4*CLK_PERIOD);
    rst <= 0;
    @(posedge clk);
endtask

task set_seed(
    input logic [7:0] seed_to_set
);
    seed       <= seed_to_set;
    seed_valid <= 1;
    #(CLK_PERIOD);
    @(posedge clk);
    seed_valid <= 0;
    #(CLK_PERIOD);
    @(posedge clk);
endtask

initial begin
    init();

    set_seed(0);

    gen_out.ready <= 1;
    #(32*CLK_PERIOD);
    gen_out.ready <= 0;
    @(posedge clk);
    #(4*CLK_PERIOD);
end

endmodule