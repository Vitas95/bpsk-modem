module modem_rx (
    input clk,
    input rst,

    axis_if.slave rx_signal,
    axis_if.master rx_data,

    input bpsk_rx_pkg::rx_ctrl_t rx_ctrl,
    output bpsk_rx_pkg::rx_status_t rx_status
);

import bpsk_rx_pkg::*;
import bpsk_modem_pkg::*;

axis_if #(.DATA_WIDTH(1), .HAS_READY(1)) prbs_if();

logic [HEADER_LEN-1 : 0]     received_header;
logic [$clog2(DATA_LEN)-1:0] bist_pkt_bit_err;

logic [FRAME_CNT_LEN-1:0] packet_num; 
logic                     packet_num_valid;

///////////////////
// Baseband part //
///////////////////

prbs_gen prbs_gen_inst (
    .clk(clk),
    .rst(rst),

    .seed(packet_num),
    .seed_valid(packet_num_valid),

    .gen_out(prbs_if)
);

deframer #(
    .HEADER_LEN(HEADER_LEN),
    .FRAME_CNT_LEN(FRAME_CNT_LEN),
    .DATA_LEN(DATA_LEN),
    .CRC_LEN(CRC_LEN),
    .BARKER(BARKER),
    .PRBS_SEED(PRBS_SEED)
) deframer_inst (
    .clk(clk),
    .rst(rst),

    .s_axis_samples(rx_signal),
    .s_axis_prbs(prbs_if),
    .m_axis(rx_data),

    // PRSB control
    .packet_num(packet_num),
    .packet_num_valid(packet_num_valid),

    // Control ports
    .deframer_en(deframer_en),
    .bist_en(bist_en),

    .deframer_busy(deframer_busy),
    .pkt_rcvd(pkt_rcvd),
    .received_header(received_header),
    .bist_pkt_bit_err(bist_pkt_bit_err),
    .crc_error(crc_error)
);

/////////////
// Control //
/////////////

rx_control #(
    .HEADER_LEN(HEADER_LEN),
    .HEADER_BIST(HEADER_BIST),
    .DATA_LEN(DATA_LEN),
    .BIST_WATCHDOG_LIMIT(BIST_WATCHDOG_LIMIT),
    .BIST_PKT_CNT(BIST_PKT_CNT)
) rx_control_inst (
    .clk(clk),
    .rst(rst),

    // Deframer control
    .deframer_en(deframer_en), 
    .bist_en(bist_en),

    // Deframer status
    .deframer_busy(deframer_busy),
    .pkt_rcvd(pkt_rcvd),
    .crc_error(crc_error),
    .bist_pkt_bit_err(bist_pkt_bit_err),
    .received_header(received_header),

    .rx_ctrl(rx_ctrl),
    .rx_status(rx_status)     
);
    
endmodule