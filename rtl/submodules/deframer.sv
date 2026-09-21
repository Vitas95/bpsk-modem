`include "axis_checks.svh"
//////////////////////////////////////////////////////////////////////////////////
// Module: framer
// Description:
//   Deframer extractthe data from the received packet. The interfaces are 
//	 AXI4-Stream compatible (with tlast).
//////////////////////////////////////////////////////////////////////////////////
//                    +---------------+          
// Input samples -+-->| Hard Decision | ---------+ 
//                |   +---------------+          |            +-----------+ CRC status  
//                |           ↑                  +----------> | CRC Check | -->
//                | +-------------------+        |            +-----------+
//                +>| Barker correlator |        v
//                  +-------------------+   +----------+                
//                            ↓             |          +-------------------> Output data 
//                    +-------------+       | Selector |  
//        ==========> | Control FSM | ====> |          |      +------------+
//  External control  +-------------+       |          +----> |            | Bit error
//                                          +----------+      | BIST Check | -->
//                                                            |            | counter and
//                          PRBS (BIST)  -------------------> |            | status
//                                                            +------------+
//
//////////////////////////////////////////////////////////////////////////////////

module deframer #(
    parameter HEADER_LEN,
    parameter FRAME_CNT_LEN,
    parameter DATA_LEN,
    parameter CRC_LEN,
    parameter BARKER,
    parameter PRBS_SEED
) (
    input clk,
    input rst,

    // Data buses
    axis_if.slave  s_axis_samples,
    axis_if.slave  s_axis_prbs,
    axis_if.master m_axis,

    // PRSB control
    output [FRAME_CNT_LEN-1:0] packet_num, 
    output                     packet_num_valid,

    // Control ports
    input logic deframer_en, // level
    input logic bist_en,     // level

    // Output status ports
    output logic                        deframer_busy,      // level, deframer found a packet and it busy now
    output logic                        pkt_rcvd,           // pulse, single packet was received, all status ports are valid 
    output logic [HEADER_LEN-1 : 0]     received_header,    // reg, header of the received packet
    output logic [$clog2(DATA_LEN)-1:0] bist_pkt_bit_err,   // reg, number of the bit error in the pacrket
    output logic                        crc_error           // level      
);

// Check data widths
`CHECK_AXIS_WIDTH(s_axis_prbs, 1)
`CHECK_AXIS_WIDTH(m_axis, 1)

// When a packet is received, there is a delay before 
// the statistics are prepared. 
// 2 clock cycles = 1 clock cycle for packet_received[0] latch + 
//                  1 clock cycle for comparing crc/received_crc 
//                  in the CRC block
localparam STAT_DELAY = 2;
logic [STAT_DELAY-1:0] pkt_rcvd_dly;
logic                  packet_finished;
always_ff @(posedge clk) begin
    pkt_rcvd_dly <= {pkt_rcvd_dly[STAT_DELAY-2:0],packet_finished};
end

assign pkt_rcvd = pkt_rcvd_dly[STAT_DELAY-1];

// Ready in input sample stream is notused.
assign s_axis_samples.ready = 1;

///////////////////////
// Barker correlator //
///////////////////////
// !!!Important!!! 
// There is no delay for the input RX signal to compensate for the Barker correlator's delay.
// The current delay is 2 clock cycles. Maximum sample rate is
// Smax = Fclk/(1+Barker_delay)  
// There is no delay line for an input signal because this 
// modem aims to sample rate that is 20 times lower than Fclk. 

localparam BARKER_THRESOHOLD = $bits(BARKER) * 2**s_axis_samples.FRACT_WIDTH;
localparam BARKER_WIDTH = s_axis_samples.DATA_WIDTH;

logic signed [BARKER_WIDTH-1 : 0]                   barker_shift_reg [$bits(BARKER)-1 : 0];
logic signed [BARKER_WIDTH : 0]                     barker_sum_reg [$bits(BARKER)-1 : 0];
logic signed [($bits(BARKER) + BARKER_WIDTH)-1 : 0] barker_out [$bits(BARKER)-1 : 0];
logic signed [($bits(BARKER) + BARKER_WIDTH)-1 : 0] barker_abs_max;
logic                                               pkt_found, pkt_inverse;

always_ff @( posedge clk ) begin
    if (rst || packet_finished) begin
        for (int i = 0; i < $bits(BARKER); i++)
            barker_shift_reg[i] <= 0;
    end else if (s_axis_samples.valid && (pkt_found == 0)) begin
        barker_shift_reg <= {barker_shift_reg[$bits(BARKER)-2:0], 
                             $signed(s_axis_samples.data)};
    end
end

always_comb begin
    for (int i = 0; i < $bits(BARKER); i++)
        if (BARKER[i] == 0)
            barker_sum_reg [i] = -barker_shift_reg[i];
        else
            barker_sum_reg [i] = barker_shift_reg[i];

    for (int i = 0; i < $bits(BARKER); i++) begin
        if (i == 0)
            barker_out[i] = barker_sum_reg[0];
        else 
            barker_out[i] = barker_out[i-1] + barker_sum_reg[i];
    end
end

always_ff @( posedge clk ) begin
    if (rst)
        barker_abs_max <= '0;
    else begin
        if (barker_out[$bits(BARKER)-1] < 0)
            barker_abs_max <= -barker_out[$bits(BARKER)-1];
        else 
            barker_abs_max <= barker_out[$bits(BARKER)-1];
    end
end

always_ff @( posedge clk ) begin
    if (rst || ~deframer_en || pkt_rcvd) begin
        pkt_found   <= 0;
        pkt_inverse <= 0;
    end else begin
        if (barker_abs_max >= BARKER_THRESOHOLD)
            pkt_found <= 1;

        // If the correlation peak is negative, the whole packet is inverted
        if ((barker_out[$bits(BARKER)-1] < 0) && pkt_found)
            pkt_inverse <= 1;
    end
end

///////////////////
// Hard dececion //
///////////////////
logic rx_bit;
logic rx_valid;

always_ff @( posedge clk ) begin
    if (rst) begin 
        rx_bit   <= 0;
        rx_valid <= 0;
    end else begin 
        rx_valid <= s_axis_samples.valid;
        if (s_axis_samples.valid)
            // High bit is 0 -> logical 1
            // High bit is 1 -> logical 0
            // + inversion after Barker correlators
            rx_bit <= (pkt_inverse) ? s_axis_samples.data[s_axis_samples.DATA_WIDTH - 1]:
                                     ~s_axis_samples.data[s_axis_samples.DATA_WIDTH - 1];
    end
end

///////////////////
// State machine //
///////////////////
typedef enum logic [2:0] { 
    IDLE, HEADER, FRAME_CNT, DATA ,CRC
} state;
state current_state;

localparam HEADER_END    = HEADER_LEN;
localparam FRAME_CNT_END = HEADER_END + FRAME_CNT_LEN;
localparam DATA_END      = FRAME_CNT_END + DATA_LEN;
localparam FRAME_END     = DATA_END   + CRC_LEN;

logic [$clog2(FRAME_END)-1:0]  sample_cnt;

always_ff @(posedge clk) begin
    if (rst || (pkt_found == 0 && rx_valid))
        sample_cnt <= '0;
    else if (rx_valid)
        sample_cnt <= sample_cnt + 1;
end

assign packet_finished = (sample_cnt == FRAME_END - 1) && rx_valid;

always_comb begin
    if      (!pkt_found)                 current_state = IDLE;
    else if (sample_cnt < HEADER_END)    current_state = HEADER;
    else if (sample_cnt < FRAME_CNT_END) current_state = FRAME_CNT;  
    else if (sample_cnt < DATA_END)      current_state = DATA; 
    else if (sample_cnt < FRAME_END) 	 current_state = CRC;
    else                                 current_state = IDLE;
end

//////////////////////
// Receiving header //
//////////////////////

always_ff @(posedge clk) begin
    if (rst) received_header <= 0;
    else if (current_state == HEADER && rx_valid)
        received_header <= {received_header[HEADER_LEN-2:0], rx_bit};
end

/////////////////////////////
// Receiving frame counter //
/////////////////////////////

logic [FRAME_CNT_LEN-1:0] frame_counter;
logic                     packet_num_ready;

always_ff @(posedge clk) begin
    if (rst) frame_counter <= 0;
    else if (current_state == FRAME_CNT && rx_valid)
        frame_counter <= {frame_counter[FRAME_CNT_LEN-2:0], rx_bit};
end

assign packet_num       = frame_counter;
assign packet_num_ready = (sample_cnt == FRAME_CNT_END);
posedge_gen posedge_gen_inst_0 (
    .clk(clk), .in(packet_num_ready), .out(packet_num_valid));

// TODO: Add some check to the received packet number

/////////////////////
// CRC calculation //
/////////////////////

logic [7:0] crc, received_crc;
logic       inv;
assign inv = rx_bit ^ crc[7];
always_ff @ (posedge clk) begin

    if (rst || pkt_rcvd_dly[0])
        crc <= '0;
    else if (current_state == DATA && rx_valid) begin
        crc <= {crc[6:2],
                crc[1] ^ inv, 
                crc[0] ^ inv,
                inv};
    end

    if (rst)
        received_crc <= '0;
    else if (current_state == CRC && rx_valid)
        received_crc <= {received_crc[6:0], rx_bit};

    if (rst || (current_state != IDLE))
        crc_error <= 0;
    else if (pkt_rcvd_dly[0]) begin
        if (crc != received_crc)
            crc_error <= 1;
        else 
            crc_error <= 0;
    end
end

//////////////////////////////
// Status output processing //
//////////////////////////////
logic [$clog2(DATA_LEN)-1:0] packet_err_cnt;

always_ff @(posedge clk) begin
    if (rst || (current_state != DATA)) begin
        m_axis.valid      <= 0;
        m_axis.data       <='0;
        s_axis_prbs.ready <= 0;
        packet_err_cnt    <= 0;
        bist_pkt_bit_err  <= 0;
    end else begin
        if (bist_en) begin
            s_axis_prbs.ready <= s_axis_samples.valid;
            if ((rx_valid && s_axis_prbs.valid) &&
                (rx_bit != s_axis_prbs.data))
                packet_err_cnt <= packet_err_cnt + 1;
            else if (sample_cnt == DATA_END-1)
                bist_pkt_bit_err <= packet_err_cnt;
        end else begin
            m_axis.valid <= rx_valid;
            m_axis.data  <= rx_bit;
            m_axis.last <= (current_state == DATA) && (sample_cnt == DATA_END-1);
        end
    end
end

assign deframer_busy = pkt_found;

endmodule