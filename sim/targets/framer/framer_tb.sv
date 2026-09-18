`timescale 1ps/1ps

module framer_tb();

import bpsk_modem_pkg::*;
    
parameter   CLK_PERIOD = 12.5;   // 80 MHz clock

bit clk, rst, packet_start;
always #(CLK_PERIOD/2) clk = ~clk;

axis_if #(.DATA_WIDTH(1), .FRACT_WIDTH(0), .HAS_READY(1)) data_out();
axis_if #(.DATA_WIDTH(1), .FRACT_WIDTH(0), .HAS_READY(1)) data_in();
axis_if #(.DATA_WIDTH(1), .FRACT_WIDTH(0), .HAS_READY(1)) prbs_in();

framer #(
    .SYNC_LEN(SYNC_LEN),
    .HEADER_LEN(HEADER_LEN),
    .FRAME_CNT_LEN(FRAME_CNT_LEN),
    .DATA_LEN(DATA_LEN),
    .CRC_LEN(CRC_LEN),
    .TAIL_LEN($size(FIR_COEFF) * 2),
    .BARKER(BARKER),
    .HEADER_DATA(HEADER_DATA),
    .HEADER_BIST(HEADER_BIST)
) dut (
    .clk(clk),
    .rst(rst),

    .s_axis_data(data_in),
    .s_axis_prbs(prbs_in),
    .m_axis(data_out),


    .packet_start(packet_start),
    .header_in(HEADER_DATA)
);

always @(posedge clk && data_in.ready) begin
    if (data_in.ready) begin
        data_in.data  <= $urandom();
        data_in.valid <= 1;
    end else begin
        data_in.data  <= '0;
        data_in.valid <= 0; 
    end
end

initial begin
    clk <= 0;
    rst <= 1;
    data_out.master.ready <= 0;
    #(4*CLK_PERIOD);
    rst <= 0;
    @(posedge clk);
    packet_start <= 1;
    data_out.master.ready <= 1;
    #(CLK_PERIOD);
    packet_start <= 0;
    #(128*CLK_PERIOD);
    @(posedge clk);
    packet_start <= 0;
end


endmodule