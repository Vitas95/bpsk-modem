module modem_tx (
    input logic clk,
    input logic rst,

    // Data interfaces
    axis_if.master tx_signal,   // Transmitting digital signal
    axis_if.slave  tx_data,     // Input bitstream to transmit

    input bpsk_tx_pkg::tx_ctrl_t tx_ctrl,
    output bpsk_tx_pkg::tx_status_t tx_status
);

import bpsk_tx_pkg::*;
import bpsk_modem_pkg::*;

///////////////////
// Baseband part //
///////////////////

// Interfaces
axis_if #(.DATA_WIDTH(1), .HAS_READY(1)) prbs_if();
axis_if #(.DATA_WIDTH(1), .HAS_READY(1)) framer_if();

// Connections
logic [7:0] header;
logic       packet_start;
logic [FRAME_CNT_LEN-1:0] packet_num; 
logic                     packet_num_valid;

prbs_gen prbs_gen_inst (
    .clk(clk),
    .rst(rst),

    .seed(packet_num),
	.seed_valid(packet_num_valid),

    .gen_out(prbs_if)
);

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
) framer_inst (
    .clk(clk),
    .rst(rst),

    // Data buses
    .s_axis_data(tx_data),
    .s_axis_prbs(prbs_if),
    .m_axis(framer_if),

    // PRSB control
    .packet_num(packet_num),
    .packet_num_valid(packet_num_valid),

    .packet_start(packet_start),
    .header_in(header)
);

/////////////
// Control //
/////////////

tx_control  #(
   .BIST_INTERPACKET_GAP(BIST_INTERPACKET_GAP),
   .BIST_PKT_CNT(BIST_PKT_CNT),
   .HEADER_BIST(HEADER_BIST)
) tx_control_inst (
    .clk(clk),
    .rst(rst),

    .packet_transmited(framer_if.last),
    .header(header),
    .packet_start(packet_start),

    .tx_ctrl(tx_ctrl),
    .tx_status(tx_status)
);

//////////////
// DSP part //
//////////////

mapper #(
    .CLK_PER_SAMPLE(CIC_R)
) mapper_inst (
    .clk(clk),
    .rst(rst),
    .data_in(framer_if),

    // At the fist stage of development mapper output will 
    // be connected to the final tx interface to check 
    // modem in internal baseband loopback.
    .data_out(tx_signal)
);
    


endmodule