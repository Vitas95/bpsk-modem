`timescale 1ps/1ps
module mapper_tb();

parameter   CLK_PERIOD = 10;

bit clk, rst;
always #(CLK_PERIOD/2) clk = ~clk;

axis_if #(.DATA_WIDTH(1), .FRACT_WIDTH(0), .HAS_READY(1)) data_in();
axis_if #(.DATA_WIDTH(2), .FRACT_WIDTH(0), .HAS_READY(0)) data_out();

mapper #(
    .CLK_PER_SAMPLE(20)
) dut (
    .clk(clk),
    .rst(rst),

    .data_in(data_in),
    .data_out(data_out)
);

always @(posedge data_in.ready) begin
    if (data_in.valid) data_in.data = $urandom();
end

initial begin
    clk <= 0;
    rst <= 1;
    data_in.valid <=  0;
    data_in.data  <= '0;
    #(4*CLK_PERIOD);
    rst <= 0;
    @(posedge clk);
    data_in.valid <= 1;
    #(200*CLK_PERIOD);
    data_in.valid <= 0;
    @(posedge clk);
    #(4*CLK_PERIOD);
end

endmodule