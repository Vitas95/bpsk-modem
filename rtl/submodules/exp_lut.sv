module exp_lut #(
    parameter int PHASE_WIDTH = 16,
    parameter int LUT_ADDR_WIDTH = 12,
    parameter int EXP_WIDTH  = 14  
) (
    input  logic                     clk,
    input  logic                     rst,
    input  logic        [PHASE_WIDTH-1:0] phase_inc,
    input  logic                          enable,              
    output logic signed [EXP_WIDTH-1:0]   sin_out, 
    output logic signed [EXP_WIDTH-1:0]   cos_out  
);

////////////
// Checks //
////////////
if (PHASE_WIDTH < LUT_ADDR_WIDTH + 2) begin : WidthCheck
    $error("exp_lut: PHASE_WIDTH must be >= LUT_ADDR_WIDTH + 2 bits");
end

////////////
// Params //
////////////
localparam int                     LUT_DEPTH = 1 << LUT_ADDR_WIDTH;
localparam int                     MAX_MAG   = (1 << (EXP_WIDTH - 1)) - 1;
localparam int                     SHIFT     = PHASE_WIDTH - LUT_ADDR_WIDTH - 2;
localparam logic [PHASE_WIDTH-1:0] QUARTER = PHASE_WIDTH'(1) << (PHASE_WIDTH - 2);

///////////////////
// Phase counter //
///////////////////
logic [PHASE_WIDTH-1:0] phase;

always_ff @(posedge clk) begin
    if (rst) 
        phase <= '0;
    else if(enable) 
        phase <= phase + phase_inc;
end

/////////////////////////// 
// Memory initialization //
///////////////////////////
logic [EXP_WIDTH-2:0] lut [0:LUT_DEPTH-1];

initial begin
    automatic real angle;
    for (int i = 0; i < LUT_DEPTH; i++) begin
        angle  = $sin((3.141592653589793 / 2.0) * (i + 0.5) / LUT_DEPTH);
        lut[i] = $rtoi(angle * MAX_MAG + 0.5);
    end
end

////////// 
// Core //
//////////
logic [1:0]                sin, cos;
logic [LUT_ADDR_WIDTH-1:0] sin_lut, cos_lut;
logic [PHASE_WIDTH-1:0]    phase_cos;

assign phase_cos = phase + QUARTER;

// Sine logic
assign sin     = phase[PHASE_WIDTH-1 -: 2];
assign sin_lut = sin[0] ? ~phase[PHASE_WIDTH-3 -: LUT_ADDR_WIDTH] 
                        :  phase[PHASE_WIDTH-3 -: LUT_ADDR_WIDTH];

// Cosine logic
assign cos     = phase_cos[PHASE_WIDTH-1 -: 2];
assign cos_lut = cos[0] ? ~phase_cos[PHASE_WIDTH-3 -: LUT_ADDR_WIDTH] 
                        :  phase_cos[PHASE_WIDTH-3 -: LUT_ADDR_WIDTH];

always_ff @(posedge clk) begin
    if (rst) begin
        sin_out <= '0;
        cos_out <= '0;
    end else begin
        if (sin[1]) 
            sin_out <= -signed'({1'b0, lut[sin_lut]});
        else                 
            sin_out <=  signed'({1'b0, lut[sin_lut]});
        if (cos[1]) 
            cos_out <= -signed'({1'b0, lut[cos_lut]});
        else                 
            cos_out <=  signed'({1'b0, lut[cos_lut]});
    end
end

endmodule
