//////////////////////////////////////////////////////////////////////////////////
// Module: rx_modem_ctrl
// Description:
//   Control / statistics module for rx_modem. Sequences rx_en / bist_en for the
//   deframer and accumulates per-session statistics (packet count, CRC error
//   count, BIST bit-error accumulation over N packets).
// 
// FSM:
//   IDLE         -- rx_en --> RX_ACTIVE
//   RX_ACTIVE    -- bist_start (deframer_en activates) --> BIST_ARMED          
//   BIST_ARMED   -- (bist_en enable here) --> BIST_ACTIVE
//   BIST_ACTIVE  -- last bist packet done or watchdog timer went off --> BIST_DONE
//   BIST_DONE    -- (bist_done pulses here) --> RX_ACTIVE
//   RX_ACTIVE    -- (!rx_en) --> IDLE   
//
//////////////////////////////////////////////////////////////////////////////////

module rx_control #(
    parameter HEADER_LEN,
    parameter HEADER_BIST,
    parameter DATA_LEN,
    parameter BIST_WATCHDOG_LIMIT,
    parameter BIST_PKT_CNT
) (
    input logic clk,
    input logic rst,

    // Deframer control
    output logic deframer_en, 
    output logic bist_en,

    // Deframer status
    input  logic                          deframer_busy,
    input  logic                          pkt_rcvd,
    input  logic                          crc_error,
    input  logic [$clog2(DATA_LEN)-1:0]   bist_pkt_bit_err,
    input  logic [HEADER_LEN-1:0]         received_header,

    input bpsk_rx_pkg::rx_ctrl_t rx_ctrl,
    output bpsk_rx_pkg::rx_status_t rx_status
);

///////////////////
// State machine //
///////////////////
typedef enum logic [2:0] {
    IDLE, RX_ACTIVE, BIST_ARMED, BIST_ACTIVE, BIST_DONE
} rx_state;
rx_state current_state, next_state;

logic bist_start_pulse, bist_run_done;
assign bist_start_pulse  = rx_ctrl.bist_start && (current_state == RX_ACTIVE);
assign bist_run_done     = rx_status.bist_sync_lost || ((rx_status.bist_pkt_cnt == BIST_PKT_CNT - 1) && pkt_rcvd);

always_comb begin
    next_state = current_state;
    unique case (current_state)
        IDLE:          
            if (rx_ctrl.rx_en)  next_state = RX_ACTIVE;

        RX_ACTIVE:
            if      (!rx_ctrl.rx_en)   next_state = IDLE;     
            else if (bist_start_pulse) next_state = BIST_ARMED;

        BIST_ARMED:
            if      (!rx_ctrl.rx_en) next_state = IDLE;
            // Switch to BIST only when deframer is available
            else if (!deframer_busy) next_state = BIST_ACTIVE;

        BIST_ACTIVE:
            if      (!rx_ctrl.rx_en) next_state = IDLE;
            // Exit from the mode if we finished or if wtchdog timer went off
            else if (bist_run_done)  next_state = BIST_DONE;
        
        BIST_DONE:
            if (!rx_ctrl.rx_en) next_state = IDLE;
            else                next_state = RX_ACTIVE;
        
        default:  next_state = IDLE;
    endcase
end

always_ff @(posedge clk) begin
    if (rst) current_state <= IDLE;
    else     current_state <= next_state;
end

///////////////
// Watchdog  //
///////////////

logic [$clog2(BIST_WATCHDOG_LIMIT)-1:0] bist_watchdog_timer;
always_ff @(posedge clk) begin
    if (rst || current_state != BIST_ACTIVE || bist_start_pulse) begin
        bist_watchdog_timer         <= '0;
        rx_status.bist_sync_lost    <=  0;
    end else if (pkt_rcvd && received_header == HEADER_BIST) begin
        bist_watchdog_timer         <= '0;
        rx_status.bist_sync_lost    <=  0;
    end else if (bist_watchdog_timer == BIST_WATCHDOG_LIMIT - 1) begin
        rx_status.bist_sync_lost    <=  1;
    end else if (!deframer_busy) begin
        bist_watchdog_timer         <= bist_watchdog_timer + 1'b1;
    end
end

///////////////////////////
// Deframer control outs //
///////////////////////////

assign deframer_en = (current_state != IDLE);
assign bist_en     = (current_state == BIST_ACTIVE);

///////////////////
// Status output //
///////////////////

always_ff @(posedge clk) begin
    if (rst || bist_start_pulse) begin
        rx_status.bist_pkt_cnt        <= '0;
        rx_status.crc_err_cnt         <= '0;
        rx_status.bist_bit_err_accum  <= '0;
        rx_status.last_header         <= '0;
    end else begin
        if (pkt_rcvd) begin
            rx_status.last_header   <= received_header;
            if (received_header == HEADER_BIST) begin
                rx_status.bist_bit_err_accum <= rx_status.bist_bit_err_accum + bist_pkt_bit_err;

                if (!bist_run_done)
                    rx_status.bist_pkt_cnt   <= rx_status.bist_pkt_cnt + 1;

                if (crc_error)
                    rx_status.crc_err_cnt <= rx_status.crc_err_cnt + 1;
            end
        end
    end
end

assign rx_status.bist_done = (current_state == BIST_DONE);
assign rx_status.bist_active = (current_state == BIST_ARMED) ||
                               (current_state == BIST_ACTIVE) || 
                               (current_state == BIST_DONE);

endmodule