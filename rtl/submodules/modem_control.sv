module modem_control #(
    parameter HEADER_LEN,
    parameter BIST_PKT_CNT
) (
    input logic clk,
    input logic rst,

    output bpsk_rx_pkg::rx_ctrl_t rx_ctrl,
    input  bpsk_rx_pkg::rx_status_t rx_status,

    output bpsk_tx_pkg::tx_ctrl_t tx_ctrl,
    input bpsk_tx_pkg::tx_status_t tx_status,

    input bpsk_modem_pkg::modem_ctrl_t modem_ctrl,
    output bpsk_modem_pkg::modem_status_t modem_status,

    // Modem core lvl signal
    output logic digital_loopback // enable digital loopback between tx and rx modem
);

///////////////////////////////
// Edge detection for        //
// level-held command inputs //
///////////////////////////////

logic bist_start_posedge, bist_clear_posedge;
posedge_gen posedge_gen_inst_0 (
    .clk(clk), .in(modem_ctrl.bist_start), .out(bist_start_posedge));
posedge_gen posedge_gen_inst_1 (
    .clk(clk), .in(modem_ctrl.bist_clear), .out(bist_clear_posedge));

///////////////////
// State mashine //
///////////////////

typedef enum logic [1:0] {
    IDLE, ACTIVE, BIST
} modem_state;
modem_state current_state, next_state;

logic bist_tx_done, bist_rx_done;
always_ff @(posedge clk) begin
    if (rst || bist_clear_posedge || bist_start_posedge) begin
        bist_tx_done <= 0;
        bist_rx_done <= 0;
    end else begin
        if (rx_status.bist_done)
            bist_rx_done <= 1;

        if (tx_status.bist_done)
            bist_tx_done <= 1;
    end
end

assign modem_status.bist_done = bist_rx_done && bist_tx_done;

always_comb begin
    next_state = current_state;
    unique case(current_state)
        IDLE:   if (modem_ctrl.modem_on) next_state = ACTIVE;
        ACTIVE: begin
            if      (bist_start_posedge)    next_state = BIST;
        end
        BIST: begin
            if      (modem_status.bist_done)    next_state = ACTIVE;
        end
    endcase
end

always_ff @(posedge clk) begin
    if (rst) current_state <= IDLE;
    else     current_state <= next_state;
end

//////////////////
// Modem status //
//////////////////

always_ff @(posedge clk) begin : statusBlock
    if (rst || bist_clear_posedge) begin
        modem_status.bist_sync_lost    <=  0;
        modem_status.crc_err_cnt       <= '0;
        modem_status.bist_bit_err_accum <= '0;
        modem_status.bist_pkt_match    <=  0; 
    end else begin
        if (rx_status.bist_done) begin
            modem_status.bist_sync_lost    <= rx_status.bist_sync_lost;
            modem_status.crc_err_cnt       <= rx_status.crc_err_cnt;
            modem_status.bist_bit_err_accum <= rx_status.bist_bit_err_accum;
            if (rx_status.bist_pkt_cnt == BIST_PKT_CNT - 1)
                modem_status.bist_pkt_match <= 1;
            else
                modem_status.bist_pkt_match <= 0;
        end
    end
end

assign modem_status.bist_active = rx_status.bist_active || tx_status.bist_active;

////////////////////////////
// Control over tx and rx //
////////////////////////////

assign rx_ctrl.rx_en = (current_state != IDLE);
assign rx_ctrl.bist_start = bist_start_posedge;

// Start tx bist only when rx is ready
logic bist_tx_start;
posedge_gen posedge_gen_inst_2 (
    .clk(clk), .in(rx_status.bist_active), .out(bist_tx_start));
assign tx_ctrl.bist_start = bist_tx_start;

assign digital_loopback = (current_state == BIST);

endmodule