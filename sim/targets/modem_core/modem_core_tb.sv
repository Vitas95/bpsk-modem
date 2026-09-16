`timescale 1ps/1ps
module modem_core_tb();

parameter   CLK_PERIOD = 10;

bit clk, rst;
always #(CLK_PERIOD/2) clk = ~clk;

axis_if #(.DATA_WIDTH(1), .FRACT_WIDTH(0), .HAS_READY(1)) data_in();
axis_if #(.DATA_WIDTH(2), .FRACT_WIDTH(0), .HAS_READY(0)) data_out();

import bpsk_modem_pkg::*;

modem_ctrl_t modem_ctrl;
modem_status_t modem_status;

axis_if #(.DATA_WIDTH(ADC_DATA_WIDTH), .FRACT_WIDTH(0)) adc_if();
axis_if #(.DATA_WIDTH(DAC_DATA_WIDTH), .FRACT_WIDTH(0)) dac_if();
axis_if #(.DATA_WIDTH(DATA_WIDTH), .FRACT_WIDTH(0), .HAS_READY(1)) tx_if();
assign tx_if.data  = '0;
assign tx_if.valid = 0;
axis_if #(.DATA_WIDTH(DATA_WIDTH), .FRACT_WIDTH(0)) rx_if();


modem_core dut(
    .clk(clk),
    .rst(rst),

    .adc_in_if(adc_if),
    .dac_out_if(dac_if),

    .tx_data_in(tx_if),
    .rx_data_out(rx_if),

    .modem_ctrl(modem_ctrl),
    .modem_status(modem_status)
);

task modem_init();
    clk <= 0;
    rst <= 1;
    modem_ctrl.bist_clear = 0;
    modem_ctrl.bist_start = 0;
    modem_ctrl.modem_on   = 0;
    #(4*CLK_PERIOD);
    @(posedge clk);
    rst <= 0;
    #(4*CLK_PERIOD);
    @(posedge clk);
    modem_ctrl.modem_on   = 1;
endtask

always @(posedge modem_status.bist_done) begin
    // Ждем один такт после флага завершения, чтобы все счетчики стабилизировались
    @(posedge clk); 
    
    $display("\n==================================================");
    $display("===           BIST EXECUTION REPORT            ===");
    $display("==================================================");
    $display(" Time of completion : %0t", $time);
    $display("--------------------------------------------------");
    
    // Вывод общего статуса прохождения теста
    if (modem_status.bist_sync_lost) begin
        $display(" STATUS             : [ FAILED ] - Synchronization lost!");
    end else if (modem_status.crc_err_cnt > 0 || 
                 modem_status.bist_bit_err_accum > 0 || 
                 modem_status.bist_pkt_match == 0) begin
        $display(" STATUS             : [ FAILED ] - Errors detected.");
    end else begin
        $display(" STATUS             : [ PASSED ] - All tests successful.");
    end
    
    $display("--------------------------------------------------");
    $display("                     DETAILS                      ");
    $display("--------------------------------------------------");
    if (modem_status.bist_pkt_match == 1) begin
        $display(" Packets Matched    : All");
    end else begin
        $display(" Packets Matched    : Packet count mismatch.");
    end
    $display(" Sync Lost Status   : %0b", modem_status.bist_sync_lost);
    $display(" CRC Error Count    : %0d", modem_status.crc_err_cnt);
    $display(" Bit Error Accum    : %0d", modem_status.bist_bit_err_accum);
    $display("==================================================\n");

    // Ваша оригинальная логика сброса BIST флагов
    #(4*CLK_PERIOD);
    @(posedge clk);
    modem_ctrl.bist_clear = 1;
    #(4*CLK_PERIOD);
    @(posedge clk);
    modem_ctrl.bist_clear = 0;
end

initial begin
    modem_init();

    #(50*CLK_PERIOD);
    @(posedge clk);
    modem_ctrl.bist_start = 1;
    #(4*CLK_PERIOD);
end

endmodule