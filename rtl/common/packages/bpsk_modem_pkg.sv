package bpsk_modem_pkg;

    // Top level data width
    localparam int ADC_DATA_WIDTH = 8;
    localparam int DAC_DATA_WIDTH = 8;
    localparam int DATA_WIDTH = 1;
    
    // Frame parameter
    //+----------------------------+---------+---------------+----------------+-----+--------------+
    //| Preamble (Sync + Barker13) | Header  | Frame counter | Payload (Data) | CRC | Tail (zeros) |
    //+----------------------------+---------+---------------+----------------+-----+--------------+
    localparam SYNC_LEN       = 64 - 13; // WO taking into account Barker frame marker
    localparam HEADER_LEN     = 8;       // Internal modem data
    localparam FRAME_CNT_LEN  = 8;       // Frame counter
    localparam DATA_LEN       = 1024;    // Transmited data
    localparam CRC_LEN        = 8;       // CRC8 
    localparam FRAME_LEN      = SYNC_LEN + 13 + HEADER_LEN + FRAME_CNT_LEN + DATA_LEN + CRC_LEN;

    localparam logic [12:0] BARKER    = 13'b1_1111_0011_0101;
    localparam logic [7:0]  PRBS_SEED = 8'd128;

    localparam BIST_PKT_CNT = 16; // Number of packets during BIST run 

    // Header parameters
    localparam logic [HEADER_LEN-1:0] HEADER_DATA    = 8;  // Real data transmission
    localparam logic [HEADER_LEN-1:0] HEADER_BIST    = 16; // BIST mode in operation
    localparam logic [HEADER_LEN-1:0] HEADER_SERVICE = 24; // Service packet to check the link TODO: Add this to the project

    // DSP parameters
    localparam FIR_COEFF_WIDTH = 16;
    localparam logic [FIR_COEFF_WIDTH-1:0] FIR_COEFF [0:6] = '{
    2, -12, -4, 26, 78, 128, 150
    };

    localparam CIC_R = 20;  // Upsampling factor, must be greater than 2!
    localparam CIC_N = 4;   // Number of stages
    localparam CIC_D = 1;   // Differential delay

     // Timing constants
    localparam BIST_INTERPACKET_GAP = 1024; // Time interval between two packets in BIST mode.
    localparam BIST_WATCHDOG_LIMIT = (BIST_INTERPACKET_GAP + SYNC_LEN + 13 + HEADER_LEN) * CIC_R; // Clk cycles without pkt_rcvd before sync_lost in the BIST mode

    // Input control of the modem control
    typedef struct packed {
        logic modem_on;   // level, converted in posedge; switch on tx and rx modem
        logic bist_start; // level, converted in posedge; switch on bist mode
        logic bist_clear; // level, converted in posedge; clear bist statistics
    } modem_ctrl_t;

    // Output status of the modem control
    typedef struct packed {
        logic                                       bist_done;         // level
        logic                                       bist_active;       // level
        logic                                       bist_sync_lost;    // reg, status if the BIST run
        logic                                       bist_pkt_match;    // level, n of packets corresponds to the BIST run     
        logic [$clog2(BIST_PKT_CNT)-1:0]            crc_err_cnt;       // reg, total number of the crc errors
        logic [$clog2(BIST_PKT_CNT * DATA_LEN)-1:0] bist_bit_err_accum;// reg, number of bit errors during BIST run
    } modem_status_t;

endpackage