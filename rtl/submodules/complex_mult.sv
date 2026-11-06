`include "axis_checks.svh"

// Iterative complex multiplier on a single DSP48A1
// (a + jb) * (c + jd) = (ac - bd) + j(ad + bc)

module complex_mult (
    input logic clk,
    input logic rst,

    axis_if.slave  s_axis_a,
    axis_if.slave  s_axis_b,
    axis_if.master m_axis
);

`CHECK_COMPLEX_FIELD(s_axis_a, 1)
`CHECK_COMPLEX_FIELD(s_axis_b, 1)
`CHECK_COMPLEX_FIELD(m_axis, 1)

localparam DATA_WIDTH = (s_axis_a.DATA_WIDTH);

////////////
// Checks //
////////////

if (DATA_WIDTH > 17) begin : DataWidthCheck
    $error("complex_mult_iter: DATA_WIDTH must be <= 17 (DSP48A1 pre adder is 18 bit)");
end

if (s_axis_a.FRACT_WIDTH != s_axis_a.FRACT_WIDTH) begin : FractionWidthCheck
    $error("complex_mult_iter: suports only equal fractional parts");
end

/////////////
// Structs //
/////////////

typedef struct packed {
    logic signed [DATA_WIDTH-1:0] Im;
    logic signed [DATA_WIDTH-1:0] Re;
} complex;

// State mashine
typedef enum logic [1:0] { 
    IDLE,
    CALC,
    VALID
 } state;

state current_state, next_state;

////////////////////
// Hold registers //
////////////////////
complex hold_a, hold_b;
logic a_flag, b_flag;

// Input pipline
logic valid;

// Start only when both samples are here, the multiplier is free
// and the previous start is already passed to the SM
logic start;
assign start = a_flag & b_flag & (current_state == IDLE) & ~valid;

always_ff @(posedge clk) begin : HoldReg
    if (rst) begin
        hold_a <= '0;
        hold_b <= '0;
        a_flag <= 0;
        b_flag <= 0;
    end else begin
        // Pair is taken to the working registers, new sample below has priority
        if (start) begin
            a_flag <= 0;
            b_flag <= 0;
        end

        if (s_axis_a.valid) begin
            hold_a <= s_axis_a.data;
            a_flag <= 1;
        end

        if (s_axis_b.valid) begin
            hold_b <= s_axis_b.data;
            b_flag <= 1;
        end
    end
end

always_ff @(posedge clk) begin : InPipeline
    if (rst) begin
        valid <= 0;
    end else begin
        valid <= start;
    end
end

// Sample registers
// Operands must stay stable during all 3 multiplications,
// so we copy the pair from hold registers when the calculation starts.
complex in_a, in_b;

always_ff @(posedge clk) begin : InputReg
    if (rst) begin
        in_a <= '0;
        in_b <= '0;
    end else if (start) begin
        in_a <= hold_a;
        in_b <= hold_b;
    end else begin
        in_a <= in_a;
        in_b <= in_b;
    end
end

// During the calculation counter is enable in order to change
// input data on a DSP cell inputs.
logic [2:0] calculation_counter;
always_ff @(posedge clk) begin
    if (rst || calculation_counter == 4) begin
        calculation_counter <= 0;
    end else if (current_state == CALC) begin
        calculation_counter <= calculation_counter + 1;
    end
end

always_comb begin : ComplexMultSM
    case(current_state)
        IDLE: begin
            if (valid) next_state = CALC;
            else       next_state = IDLE;
        end

        CALC: begin
            if (calculation_counter == 4) next_state = VALID;
            else  next_state = CALC;
        end

        VALID: next_state = IDLE;

        default: next_state = IDLE;
    endcase
end

always_ff @(posedge clk) begin : SM
    if (rst) current_state <= IDLE;
    else     current_state <= next_state;
end

/////////////////////////////////
// Single DSP48A1 (behavioral) //
/////////////////////////////////
logic signed [17:0] b, b_reg;
logic signed [17:0] pre_adder_comb, pre_adder_reg;
(* use_dsp = "yes" *) logic signed [47:0] mult;
logic signed [47:0] c_reg;       // DSP C port, holds k1
logic signed [47:0] post_adder;
logic signed [47:0] im_reg;

always_comb begin : PreAdder
    case(calculation_counter)
        3'd0: begin 
            pre_adder_comb = in_a.Re + in_a.Im;     // a + b
            b = in_b.Re;                            // c
        end

        3'd1: begin
            pre_adder_comb = in_b.Im - in_b.Re;     // d - c
            b = in_a.Re;                            // a
        end

        3'd2: begin
            pre_adder_comb = in_b.Re + in_b.Im;     // c + d
            b = in_a.Im;                            // b
        end

        default: begin
            pre_adder_comb = in_a.Re + in_a.Im;
            b = in_b.Re;
        end
    endcase    
end

always_ff @( posedge clk ) begin : CombToReg
    pre_adder_reg <= pre_adder_comb;
    b_reg <= b;
end

always_ff @( posedge clk ) begin : MultiplyAccumulate
    
    // Multiplication always work
    mult <= pre_adder_reg * b_reg;
    
    // As well as post adder
    if (rst) begin
        c_reg <= '0;
        post_adder <= '0;
        im_reg <= '0;
    end else if (calculation_counter == 2) begin
        c_reg <= mult;                      // k1 = c * (a + b): save to C port
    end else if (calculation_counter == 3) begin
        post_adder <= c_reg + mult;         // k2 = a * (d - c): Im = k1 + k2
    end else if (calculation_counter == 4) begin
        post_adder <= c_reg - mult;         // k3 = b * (c + d): Re = k1 - k3
        im_reg <= post_adder;               // keep Im, post adder is reused for Re
    end
end

////////////////////
// Result scaling //
////////////////////
complex result;
always_comb begin : ResultScale
    result.Re = post_adder >>> s_axis_a.FRACT_WIDTH;
    result.Im = im_reg >>> s_axis_a.FRACT_WIDTH;
end

//////////////////////
// Output piplining //
//////////////////////
always_ff @(posedge clk) begin
    if (current_state == VALID) begin
        m_axis.valid <= 1;
    end else begin
        m_axis.valid <= 0;
    end

    if (rst)
        m_axis.data <= '0;
    else if (current_state == VALID) 
        m_axis.data <= result;
end

endmodule