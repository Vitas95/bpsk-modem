package bpsk_rx_pkg;

// Fixed point parameters for all signed data interfaces between all DSP 
// blocks in the receiver. 
//        DDC_IF        CIC_IF       FIR_IF        SYNC_IF
// +-----+  \/  +-----+  \/  +-----+  \/   +------+  \/   +----------+
// | DDC | ====>| CIC | ====>| FIR | ====> | SYNC | ====> | Deframer |
// +-----+      +-----+      +-----+       +------+       +----------+
localparam DDC_DATA_WIDTH  = 16;
localparam DDC_FIXED_WIDTH = 14;
localparam CIC_DATA_WIDTH  = 16;
localparam CIC_FIXED_WIDTH = 14;
localparam FIR_DATA_WIDTH  = 16;
localparam FIR_FIXED_WIDTH = 14;
localparam SYNC_DATA_WIDTH  = 16;
localparam SYNC_FIXED_WIDTH = 14;

// Input control of the rx control
typedef struct packed {
    logic   rx_en;       // level, enable all rx part of the module  
    logic   bist_start;  // pulse, request a BIST run
} rx_ctrl_t;

// Output status of the rx control
typedef struct packed {
    logic                                                                        bist_done;          // pulse, measurement cycle done
    logic                                                                        bist_active;        // level
    logic                                                                        bist_sync_lost;     // level, watchdog timer caught packet lost
    logic [$clog2(bpsk_modem_pkg::BIST_PKT_CNT)-1:0]                             bist_pkt_cnt;       // reg, total number of received packets with a BIST header
    logic [$clog2(bpsk_modem_pkg::BIST_PKT_CNT)-1:0]                             crc_err_cnt;        // reg, total number of the crc errors
    logic [$clog2(bpsk_modem_pkg::BIST_PKT_CNT * bpsk_modem_pkg::DATA_LEN)-1:0]  bist_bit_err_accum; // reg, total number of a bit errors
    logic [bpsk_modem_pkg::HEADER_LEN-1:0]                                       last_header;        // reg, last received header
} rx_status_t;


endpackage