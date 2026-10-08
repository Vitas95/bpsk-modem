package bpsk_tx_pkg;


// Fixed point parameters for all signed data interfaces between all DSP 
// blocks in the transmitter. 
//           FIR_IF        CIC_IF        DUC_IF
// +--------+  \/   +-----+  \/   +-----+  \/   +-----+
// | Mapper | ====> | FIR | ====> | CIC | ====> | DUC |
// +--------+       +-----+       +-----+       +-----+
localparam FIR_DATA_WIDTH  = 2;
localparam FIR_FRACT_WIDTH = 0;
localparam CIC_DATA_WIDTH  = 16;
localparam CIC_FRACT_WIDTH = 14;
localparam DUC_DATA_WIDTH  = 16;
localparam DUC_FRACT_WIDTH = 14;

// Input control of the tx control
typedef struct packed {
    logic bist_start;    // pulse, start BIST mode
} tx_ctrl_t;

// Output status of the tx control
typedef struct packed {
    logic bist_active;  // level, 1 while a run is sending packets or waiting out a gap
    logic bist_done;    // pulse, inform that the requested number of packets has been sent
} tx_status_t;

endpackage

