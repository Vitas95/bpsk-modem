`timescale 1ps/1ps

module modem_tx_tb ();

parameter   CLK_PERIOD = 10;

bit clk, rst, tx_en, packet_start;
always #(CLK_PERIOD/2) clk = ~clk;

logic [7:0] header = 16;

axis_if #(.DATA_WIDTH(2), .HAS_READY(0)) tx_data_if();
axis_if #(.DATA_WIDTH(1), .HAS_READY(1)) rx_data_if();

modem_tx dut (
    .clk(clk),
    .rst(rst),

    .tx_signal(tx_data_if),
    .tx_data(rx_data_if)
);

initial begin
    clk <= 0;
    rst <= 1;
    #(4*CLK_PERIOD);
    rst <= 0;
    @(posedge clk);
    packet_start <= 1;
    #(128*CLK_PERIOD);
    @(posedge clk);
    packet_start <= 0;
end

endmodule