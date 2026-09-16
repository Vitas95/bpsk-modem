interface axis_if #(
    parameter DATA_WIDTH  = 1,
    parameter FRACT_WIDTH = 0,
    parameter COMPLEX     = 0,
    parameter HAS_READY   = 0,
    parameter HAS_LAST    = 0
);

localparam FINAL_DATA_WIDH = DATA_WIDTH * (1 + COMPLEX);

logic [FINAL_DATA_WIDH-1:0] data;
logic valid;
logic ready;
logic last;

modport master  (output data, valid, last, 
                 input ready);

modport slave   (input data, valid, last,
                 output ready);
                 
modport monitor (input data, valid, ready, last);


endinterface