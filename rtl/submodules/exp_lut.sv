module exp_lut #(
    parameter int PHASE_WIDTH = 10,  
    parameter int EXP_WIDTH  = 15  
) (
    input  logic                     clk,
    input  logic                     rst,
    output logic signed [EXP_WIDTH-1:0] sin_out, 
    output logic signed [EXP_WIDTH-1:0] cos_out  
);

// Phase increment
logic [PHASE_WIDTH-1:0] phase, phase_inc;

// delta_phi = int(F_out / F_clk * 2**16)
// delta_phi = int(10e6 / 80e6 * 65536) = 8192
// So initial frequency is 10 MHz.
// Maximum frequency - 30 MHz, minimum - 0.15625 MHz.
assign phase_inc = 16'd8192;

// Phase counter
always_ff @(posedge clk) begin
    if (rst) phase <= 0;
    else phase <= phase + phase_inc;
end

localparam int LUT_DEPTH = 1 << (PHASE_WIDTH - 2);
localparam int MAX_MAG   = (1 << (EXP_WIDTH - 1)) - 1;

logic [EXP_WIDTH-2:0] lut [0:LUT_DEPTH-1]; // TODO: Remove dependence of the lut depth from the phase counter width

// Memory initialization
initial begin
    automatic real angle;
    for (int i = 0; i < LUT_DEPTH; i++) begin
        // Quantization from 0 to pi/2
        angle = $sin((2.0 * 3.141592653589793 * i) / (1 << PHASE_WIDTH));
        lut[i] = $rtoi(angle * MAX_MAG);
    end
end

logic [1:0]             sin, cos;
logic [PHASE_WIDTH-3:0] sin_lut, cos_lut;
logic [PHASE_WIDTH-1:0] phase_cos;

assign phase_cos = phase + LUT_DEPTH; 

// Sine logic
assign sin     = phase[PHASE_WIDTH-1:PHASE_WIDTH-2];
assign sin_lut = sin[0] ? ~phase[PHASE_WIDTH-3:0] : phase[PHASE_WIDTH-3:0];

// Cosine logic
assign cos     = phase_cos[PHASE_WIDTH-1:PHASE_WIDTH-2];
assign cos_lut = cos[0] ? ~phase_cos[PHASE_WIDTH-3:0] : phase_cos[PHASE_WIDTH-3:0];

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
