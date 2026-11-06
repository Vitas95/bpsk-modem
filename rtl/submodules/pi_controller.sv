module pi_controller #(
    parameter COEFF_WIDTH
)(
    input logic clk,
    input logic rst,

    input logic [COEFF_WIDTH-1:0] Ki,
    input logic [COEFF_WIDTH-1:0] Kp,

    axis_if.slave s_axis,
    axis_if.master m_axis
);

////////////
// Checks //
////////////
if (COEFF_WIDTH > 17) begin : CoefficientsWidthCheck
    $error("pi_controller: COEFF_WIDTH must be <= 17 (unsigned coefficient + sign bit for DSP48A1)");
end

///////////////////
// Input pipline //
///////////////////
logic valid;

always_ff @(posedge clk) begin : InPipeline
    if (rst) begin
        valid <= 0;
    end else begin
        valid <= s_axis.valid;
    end
end

///////////////////
// State mashine //
///////////////////
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

always_comb begin : PISM
    case(current_state)
        IDLE: begin
            if (valid) next_state = CALC;
            else       next_state = IDLE;
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

/////////////////////////////////
// Single DSP48A1 (behavioral) //
/////////////////////////////////
(* use_dsp = "yes" *) logic signed [17:0] a, a_reg, b, b_reg;
(* use_dsp = "yes" *) logic signed [47:0] mult;
(* use_dsp = "yes" *) logic signed [47:0] post_adder, c;
logic signed [47:0] integrator;

always_comb begin
    case(calculation_counter)
    2'b00:   b = signed'(18'(Ki));
    2'b01:   b = signed'(18'(Kp));
    default: b = signed'(18'(Ki));
    endcase
end

assign a = $signed(s_axis.data);
assign c = integrator;

always_ff @( posedge clk ) begin : CombToReg
    a_reg <= a;
    b_reg <= b;
end

logic mac_enable, save_integrator;
assign mac_enable = (current_state == CALC) && ~(calculation_counter == 2) ;
assign save_integrator = (calculation_counter == 1);

always_ff @( posedge clk ) begin : MultiplyAccumulate

    if (rst)                  integrator <= 0;
    else if (save_integrator) integrator <= post_adder;
    else                      integrator <= integrator;
    
    // Multiplication always work
    mult <= a_reg * b_reg;
    
    // As well as post adder
    if (mac_enable) post_adder <= c + mult;
    else            post_adder <= mult;
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
        m_axis.data <= post_adder >>> (COEFF_WIDTH-1);
end

endmodule