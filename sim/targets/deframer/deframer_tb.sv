import bpsk_modem_pkg::*;

module deframer_tb ();

parameter   CLK_PERIOD = 10;   // 80 MHz clock

bit clk, rst, deframer_en, bist_en;
always #(CLK_PERIOD/2) clk = ~clk;

axis_if #(.DATA_WIDTH(1), .FRACT_WIDTH(0), .HAS_READY(0)) rx_data();
axis_if #(.DATA_WIDTH(2), .FRACT_WIDTH(0), .HAS_READY(0)) rx_signal();
axis_if #(.DATA_WIDTH(1), .FRACT_WIDTH(0), .HAS_READY(1)) prbs_in();

deframer #(
    .HEADER_LEN(HEADER_LEN),
    .FRAME_CNT_LEN(FRAME_CNT_LEN),
    .DATA_LEN(16),
    .CRC_LEN(CRC_LEN),
    .BARKER(BARKER),
    .PRBS_SEED(PRBS_SEED)
) dut (
    .clk(clk),
    .rst(rst),

    .s_axis_samples(rx_signal),
    .s_axis_prbs(prbs_in),
    .m_axis(rx_data),

    // Control ports
    .deframer_en(deframer_en),
    .bist_en(bist_en)
);

import tb_pkg::*;

tb_pkg::pulse_driver #(2) drv_a = new(rx_signal);

always @(posedge prbs_in.ready) begin
    prbs_in.data = 0;
    prbs_in.valid = 1;
    @(posedge clk);
    prbs_in.data = 0;
    prbs_in.valid = 0;
end

initial begin
    clk <= 0;
    rst <= 1;
    deframer_en <= 0;
    bist_en <= 0;
    prbs_in.data = 0;
    prbs_in.valid = 0;
    #(4*CLK_PERIOD);
    rst <= 0;
    @(posedge clk);
    deframer_en <= 1;
    bist_en <= 1;
    #(CLK_PERIOD);
    @(posedge clk);
    bist_en <= 0;
    drv_a.apply_pulse_from_file (clk, "../test_data.txt", 4, 0);
    @(posedge clk);
end

endmodule