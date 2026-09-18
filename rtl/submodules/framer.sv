`include "axis_checks.svh"
//////////////////////////////////////////////////////////////////////////////////
// Module: framer
// Description:
//   Framer form the transmittion packet. The interfaces are 
//	 AXI4-Stream compatible (with tready and tlast).
//////////////////////////////////////////////////////////////////////////////////
//                        +---------+
//      Sync + Barker  ---+         |
//                        |         |
// Header + frame cnt  ---+         |
//                        |         |
//      External data  ---+         | 
//                        |   MUX   | -------> Ready frame for a Mapper
//        PRBS (BIST)  ---+         |          (Ready/Valid interface)
//                        |         |
//                CRC  ---+         |
//                        |         |
//       Tail (zeros)  ---+         |
//                        |         |
//                        +---------+
//                            /\
//                            ||
//                     +--------------+
//                     | Control (FSM)| <=== Data from Tx Control state machine 
//                     +--------------+
//

module framer #(
    parameter SYNC_LEN,
    parameter HEADER_LEN,
    parameter FRAME_CNT_LEN,
    parameter DATA_LEN,
    parameter CRC_LEN,
    parameter TAIL_LEN,
    parameter BARKER,
    parameter HEADER_DATA,
    parameter HEADER_BIST
)(
    input clk,
    input rst,

    // Data buses
    axis_if.slave  s_axis_data,
    axis_if.slave  s_axis_prbs,
    axis_if.master m_axis,

    // PRSB control
    output [FRAME_CNT_LEN-1:0] packet_num, 
    output                     packet_num_valid,

    // Control ports
    input                        packet_start,  // pulse, start frame transmission
    input logic [HEADER_LEN-1:0] header_in      // reg, current header value
);

// All data are single bit buses
`CHECK_AXIS_WIDTH(s_axis_data, 1)
`CHECK_AXIS_WIDTH(s_axis_prbs, 1)
`CHECK_AXIS_WIDTH(m_axis, 1)

///////////////////
// State machine //
///////////////////
typedef enum logic [2:0] { 
    IDLE, PREAMBLE, HEADER, FRAME_CNT, DATA, CRC, TAIL 
} state;
state current_state;

localparam PREAMBLE_END  = SYNC_LEN + $bits(BARKER);
localparam HEADER_END    = PREAMBLE_END + HEADER_LEN;
localparam FRAME_CNT_END = HEADER_END + FRAME_CNT_LEN;
localparam DATA_END      = FRAME_CNT_END + DATA_LEN;
localparam CRC_END       = DATA_END + CRC_LEN;
localparam FRAME_END     = CRC_END + TAIL_LEN; 

logic [$clog2(CRC_END)-1:0]  sample_cnt;

logic advance;
assign advance  = m_axis.ready && m_axis.valid; // Data was transfered to the slave

// This block is designed to send only one packet,
// so this register set with an external enable signal
// and reset when packet is finished
logic enable;
always_ff @(posedge clk) begin
    if (rst || sample_cnt == FRAME_END - 1) enable <= 0;
    else if (packet_start)                         enable <= 1;
end

always_comb begin
    if      (!enable)                    current_state = IDLE;
    else if (sample_cnt < PREAMBLE_END)  current_state = PREAMBLE; 
    else if (sample_cnt < HEADER_END)    current_state = HEADER;
    else if (sample_cnt < FRAME_CNT_END) current_state = FRAME_CNT;
    else if (sample_cnt < DATA_END)      current_state = DATA; 
    else if (sample_cnt < CRC_END) 	     current_state = CRC;
    else if (sample_cnt < FRAME_END)     current_state = TAIL;
    else                                 current_state = IDLE;
end

always_ff @(posedge clk) begin
    if (rst || current_state == IDLE)
        sample_cnt <= '0;
    else if (advance)
        sample_cnt <= sample_cnt + 1;
end

/////////////////////////
// Preamble generation //
/////////////////////////
logic                       preamble;
logic [$bits(BARKER)-1:0]   barker;

always_ff @ (posedge clk) begin
    if (rst || current_state == IDLE) 
        barker <= BARKER;
    else if (advance && (sample_cnt >= SYNC_LEN) && (sample_cnt < PREAMBLE_END)) 
        barker <= {barker[$bits(BARKER)-2:0], barker[$bits(BARKER)-1]};
end

assign preamble = (sample_cnt < SYNC_LEN) ? sample_cnt[0]:barker[$bits(BARKER)-1];

///////////////////////
// Header generation //
///////////////////////

logic [HEADER_LEN-1:0] header;
always_ff @(posedge clk) begin
    if (rst || (current_state == IDLE)) 
        header <= header_in;
    else if (advance && (sample_cnt >= PREAMBLE_END) && (sample_cnt < HEADER_END))
            header  <= {header[HEADER_LEN-2:0], header[HEADER_LEN-1]};
        else 
            header <= header;
end

///////////////////
// Frame counter //
///////////////////
logic [FRAME_CNT_LEN-1:0] frame_counter;
logic                     packet_num_ready;

always_ff @(posedge clk) begin
    if (rst)
        frame_counter <= '0;
    else if (packet_start)
        frame_counter <= frame_counter + 1;
    else if (advance && (current_state == FRAME_CNT))
        frame_counter  <= {frame_counter[FRAME_CNT_LEN-2:0], frame_counter[FRAME_CNT_LEN-1]};
end

assign packet_num       = frame_counter;
assign packet_num_ready = (sample_cnt == FRAME_CNT_END);
posedge_gen posedge_gen_inst_0 (
    .clk(clk), .in(packet_num_ready), .out(packet_num_valid));

////////////////////
// CRC generation //
////////////////////

logic [7:0] crc;
logic       inv;
assign inv = m_axis.data ^ crc[7];
always_ff @ (posedge clk) begin
    if (rst || current_state == IDLE)
        crc <= '0;
    else if (advance && current_state == DATA) begin
        crc <= {crc[6:2],
                crc[1] ^ inv, 
                crc[0] ^ inv,
                inv}; 
    end else if (advance && current_state == CRC)
        crc <= {crc[6:0], crc[7]};
end

//////////////////
// Output logic // 
//////////////////

always_comb begin
    m_axis.data       = '0;
    m_axis.valid      = (current_state != IDLE);
    s_axis_data.ready = 1'b0;
    s_axis_prbs.ready = 1'b0;

    unique case (current_state)
        PREAMBLE:   m_axis.data = preamble;
        HEADER:     m_axis.data = header[7];
        FRAME_CNT:  m_axis.data = frame_counter[7];
        
        DATA: begin
            if (header == HEADER_DATA) begin
                m_axis.data       = s_axis_data.data;
                m_axis.valid      = s_axis_data.valid;
                s_axis_data.ready = m_axis.ready;
            end else if (header == HEADER_BIST) begin
                m_axis.data       = s_axis_prbs.data;
                m_axis.valid      = s_axis_prbs.valid;
                s_axis_prbs.ready = m_axis.ready;
            end else begin
                m_axis.valid = 1'b0;
            end
        end

        CRC:     m_axis.data = crc[7];
        default: m_axis.valid = 1'b0;

        TAIL:    m_axis.data = 0;
    endcase
end

assign m_axis.last = (current_state == TAIL) &&
                     (sample_cnt == FRAME_END - 1) &&
                     (m_axis.valid == 1);

endmodule