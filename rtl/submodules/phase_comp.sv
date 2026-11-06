`include "axis_checks.svh"
module phase_comp #(
    parameter PHASE_WIDTH,
    parameter STAGES
) (
    input logic clk,
    input logic rst,

    axis_if.slave s_axis,
    axis_if.slave s_axis_phase,
    axis_if.master m_axis
);

`CHECK_COMPLEX_FIELD(s_axis, 1)
`CHECK_COMPLEX_FIELD(m_axis, 1)

// Sine and cosine have only a fractional part and a sign as a MSB
logic [PHASE_WIDTH-1:0] phase_inc;
assign phase_inc = -s_axis_phase.data;

logic signed [14 : 0] sin_out, cos_out;
exp_lut #(            
    .EXP_WIDTH(15),
    .LUT_ADDR_WIDTH(12),   
    .PHASE_WIDTH(PHASE_WIDTH)
) exp_lut_inst (      
    .clk(clk),        
    .rst(rst),
    .phase_inc(phase_inc),
    .enable(s_axis_phase.valid),        
    .sin_out(sin_out),    
    .cos_out(cos_out)     
);

axis_if #(.DATA_WIDTH(16), .FRACT_WIDTH(14), .COMPLEX(1))   exp();
logic                                                       valid_delay; 

// Enhance to 16 bit width
assign exp.data = {sin_out[14], sin_out, cos_out[14], cos_out};

always_ff @(posedge clk) begin
    if (rst) begin 
        valid_delay <= 0;
        exp.valid   <= 0;
    end else begin
        valid_delay <= s_axis.valid;
        exp.valid   <= valid_delay;
    end
end

complex_mult complex_mult_inst(
    .clk(clk),
    .rst(rst),

    .s_axis_a(s_axis),
    .s_axis_b(exp),
    .m_axis(m_axis)
);

endmodule