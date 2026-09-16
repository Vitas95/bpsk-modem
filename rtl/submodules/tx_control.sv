//////////////////////////////////////////////////////////////////////////////////
// Module: tx_control
// Description:
//   Controls the start of a packet and sets the packet header for the framer.
//   Currently only the BIST mode is available: on a bist_start pulse it fires
//   BIST_PKT_CNT packets, spaced by BIST_INTERPACKET_GAP idle cycles.
//
// FSM:
//   IDLE    -- bist_start --> SEND
//   SEND    -- (packet_start pulses here) --> WAIT_TX          
//   WAIT_TX -- packet_transmited, more packets left --> GAP
//   WAIT_TX -- packet_transmited, last packet done  --> DONE
//   GAP     -- gap elapsed --> SEND
//   DONE    -- (bist_done pulses here) --> IDLE   
//
//////////////////////////////////////////////////////////////////////////////////

module tx_control #(
    parameter BIST_INTERPACKET_GAP,
    parameter BIST_PKT_CNT,
    parameter HEADER_BIST
)(
    input logic clk,
    input logic rst,

    // Framer control
    output logic [$bits(HEADER_BIST)-1:0] header,
    output logic                          packet_start,
    
    // Framer status
    input logic packet_transmited,

    input bpsk_tx_pkg::tx_ctrl_t tx_ctrl,
    output bpsk_tx_pkg::tx_status_t tx_status
);

// At the current stage of modem baseband psrt development, only BIST mode is available.
assign header = HEADER_BIST;

///////////////////
// State machine //
///////////////////

typedef enum logic [2:0] { 
    IDLE, SEND, WAIT_TX, GAP, DONE
} tx_state;
tx_state current_state, next_state;

logic [$clog2(BIST_INTERPACKET_GAP)-1:0] bist_gap_cnt;
logic [$clog2(BIST_PKT_CNT)-1:0]         bist_pkt_cnt;

wire last_packet = (bist_pkt_cnt == BIST_PKT_CNT - 1);
wire gap_elapsed = (bist_gap_cnt == BIST_INTERPACKET_GAP - 1);
wire start_req   =  tx_ctrl.bist_start && (current_state == IDLE);

always_comb begin
    next_state = current_state;
    unique case (current_state)
        IDLE:       if (start_req)         next_state = SEND;
        SEND:                              next_state = WAIT_TX;
        WAIT_TX:    if (packet_transmited) next_state = last_packet ? DONE : GAP;
        GAP:        if (gap_elapsed)       next_state = SEND;
        DONE:                              next_state = IDLE;
        default:                           next_state = IDLE;
    endcase
end

always_ff @(posedge clk) begin
    if (rst) current_state <= IDLE;
    else     current_state <= next_state;
end

/////////////////////////
// Counters and status //
/////////////////////////

always_ff @(posedge clk) begin
    if (rst || start_req)
        bist_pkt_cnt <= '0;
    else if (current_state == WAIT_TX && packet_transmited && !last_packet)
        bist_pkt_cnt <= bist_pkt_cnt + 1'b1;
end

always_ff @(posedge clk) begin
    if (rst || current_state != GAP)
        bist_gap_cnt <= '0;
    else
        bist_gap_cnt <= bist_gap_cnt + 1'b1;
end

assign packet_start           = (current_state == SEND);
assign tx_status.bist_active  = (current_state == SEND) || (current_state == WAIT_TX) || (current_state == GAP);
assign tx_status.bist_done    = (current_state == DONE);

endmodule