module horner_mac #(
    parameter DATA_WIDTH = 16,
    parameter MU_WIDTH = 16
) (
    input logic clk,
    input logic rst,

    input logic                  valid_in,
    input logic [DATA_WIDTH+4:0] c0, c1, c2, c3,
    input logic [MU_WIDTH-1:0]   mu,

    output logic signed [DATA_WIDTH:0] data_out,
    output logic                       valid_out
);

// Horner scheme:
// y(n) = ((c3 * mu + c2) * mu + c1) * mu + c0;
// It will be performed with a single DSP cell because we assume that the
// input sample rate is much slower than a clock.

// State Mashine for the multiplier part.
typedef enum logic [1:0] { 
    IDLE,
    CALC,
    VALID
 } state;

state current_state, next_state;

// Counters for the whole multiplication process
// coeff_counter will count multiplication stages in the 
// Horner scheme.
// mult_counter represents multiplication delay of the DSP
// cell.
logic [1:0] coeff_counter, mult_counter;
logic       coeff_counter_rst, mult_counter_rst;

parameter DSP_DELAY = 2;
assign coeff_counter_rst = (rst || current_state != CALC);

always_ff @(posedge clk) begin : CoeffCounter
    if (coeff_counter_rst) begin
        coeff_counter <= '0;
    end else if (current_state == CALC && mult_counter == DSP_DELAY) begin
        coeff_counter <= coeff_counter + 1;
    end 
end

assign mult_counter_rst = (rst || current_state != CALC || mult_counter == DSP_DELAY);
always_ff @(posedge clk) begin : MultCounter
    if (mult_counter_rst) mult_counter <= '0;
    else                  mult_counter <= mult_counter + 1;
end

always_comb begin : HornerSM
    case(current_state)
        IDLE: begin
            if (valid_in) next_state = CALC;
            else           next_state = IDLE;
        end

        CALC: begin
            if (coeff_counter == 2 && mult_counter == DSP_DELAY) next_state = VALID;
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

// Multiplier behavioral DSP48A1
logic signed [17:0] a, b, a_reg, b_reg;
(* use_dsp = "yes" *) logic signed [47:0] mult;
logic signed [47:0] post_adder, c, c_reg;

always_comb begin : PreAdder
    case(coeff_counter)
        2'b00: begin 
            a = $signed(c3);
            c = $signed(c2) <<< (MU_WIDTH-1);
        end

        2'b01: begin
            a =  $signed(post_adder) >>> (MU_WIDTH-1);
            c = $signed(c1) <<< (MU_WIDTH-1);
        end

        2'b10: begin
            a =  $signed(post_adder)  >>> (MU_WIDTH-1);
            c = $signed(c0) <<< (MU_WIDTH-1);
        end

        default: begin
            a = $signed(c3);
            c = $signed(c2) <<< (MU_WIDTH-1);
        end
    endcase    
end

assign b = mu;

always_ff @( posedge clk ) begin : CombToReg
    a_reg <= a;
    b_reg <= b;
    c_reg <= c;
end

always_ff @( posedge clk ) begin : MultiplyAccumulate
    
    // Multiplication always work
    mult <= a_reg * b_reg;
    
    // As well as post adder
    post_adder <= c_reg + mult;
end

// Result
always_ff @(posedge clk) begin
    if (rst) valid_out <= 0;
    else if (current_state == VALID) begin
        valid_out <= 1;
        data_out  <= $signed(post_adder) >>> (MU_WIDTH-1);
    end else begin
        valid_out <= 0;
        data_out  <= data_out;
    end
end

    
endmodule