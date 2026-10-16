`include "axis_checks.svh"

module gardner_error (
    input logic clk,
    input logic rst,

    axis_if.slave s_axis,
    //axis_if.master m_axis_data, // TODO Output the recovered symbol
    axis_if.master m_axis_error
);

`CHECK_COMPLEX_FIELD(s_axis, 1)
//`CHECK_COMPLEX_FIELD(m_axis_data, 1)

// Input pipline
logic valid;

always_ff @(posedge clk) begin : InPipeline
    if (rst) begin
        valid <= 0;
    end else begin
        valid <= s_axis.valid;
    end
end

// Sample shift register
// We always pass the data through this register.
localparam DATA_WIDTH = (s_axis.DATA_WIDTH);
typedef struct packed {
    logic signed [DATA_WIDTH-1:0] Im;
    logic signed [DATA_WIDTH-1:0] Re;
} complex;
complex shift_reg [0:2];

always_ff @(posedge clk) begin : ShiftReg
    if (valid) begin
        for (int i = 0; i < 4; i++) begin
            if (i == 0) shift_reg[0] <= s_axis.data;
            else        shift_reg[i] <= shift_reg[i-1];
        end
    end else begin
        shift_reg <= shift_reg;
    end
end

// To enable calculation we have to wait two data samples
// So we use 1 bit reg for this stateand posedge to start the SM
logic calc_flag, calc_flag_delay, calc_flag_posedge;
always_ff @(posedge clk) begin
    if (rst)        calc_flag <= 0;
    else if (valid) calc_flag <= ~calc_flag;
    else            calc_flag <= calc_flag;
    calc_flag_delay <= calc_flag;
end

assign calc_flag_posedge = calc_flag & ~ calc_flag_delay;

// State mashine
typedef enum logic [1:0] { 
    IDLE,
    CALC,
    VALID
 } state;

state current_state, next_state;

// During the calculation counter is enable in order to change
// input data on a DSP cell inputs
logic [1:0] calculation_counter;
always_ff @(posedge clk) begin
    if (rst || calculation_counter == 3) begin
        calculation_counter <= 0;
    end else if (current_state == CALC) begin
        calculation_counter <= calculation_counter + 1;
    end
end

always_comb begin : GardnerSM
    case(current_state)
        IDLE: begin
            if (calc_flag_posedge) next_state = CALC;
            else           next_state = IDLE;
        end

        CALC: begin
            if (calculation_counter == 3) next_state = VALID;
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

// Multiplier behavioral single DSP48A1
logic signed [17:0] b, b_reg;
logic signed [17:0] pre_adder_comb, pre_adder_reg;
(* use_dsp = "yes" *) logic signed [47:0] mult;
logic signed [47:0] post_adder;

always_comb begin : PreAdder
    case(calculation_counter)
        2'b00: begin 
            pre_adder_comb = shift_reg[0].Re - shift_reg[2].Re;
            b = shift_reg[1].Re;
        end

        2'b01: begin
            pre_adder_comb = shift_reg[0].Im - shift_reg[2].Im;
            b = shift_reg[1].Im;
        end

        default: begin
            pre_adder_comb = shift_reg[0].Re - shift_reg[2].Re;
            b = shift_reg[1].Re;
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
        post_adder <= '0;
    end else if (calculation_counter == 1) begin
        post_adder <= mult;                // first product (Re part): load, drops the previous result
    end else if (calculation_counter == 3) begin
        post_adder <= post_adder + mult;   // second product (Im part): accumulate
    end
end

// Output piplining
always_ff @(posedge clk) begin
    if (current_state == VALID) begin
        m_axis_error.valid <= 1;
    end else begin
        m_axis_error.valid <= 0;
    end

    if(current_state == VALID) m_axis_error.data <= post_adder;
end

endmodule