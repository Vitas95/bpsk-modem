module pi_controller (
    input logic clk,
    input logic rst,

    axis_if.slave s_axis,
    axis_if.master m_axis
);

// Input pipline
logic valid;

always_ff @(posedge clk) begin : InPipeline
    if (rst) begin
        valid <= 0;
    end else begin
        valid <= s_axis.valid;
    end
end

// PI filter perform a basic filtration of the input error into a 
// control signal with a next few formulas:
// integral     = integral + Ki * error
// proportional = Kp * error
// filter_out   = proportional + integral

localparam COEFF_WIDTH = 16;
localparam logic [COEFF_WIDTH-1:0] Ki = $floor(0.0005 * 2**(COEFF_WIDTH-1));
localparam logic [COEFF_WIDTH-1:0] Kp = $floor(0.008 * 2**(COEFF_WIDTH-1));

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

// Multiplier behavioral single DSP48A1
logic signed [17:0] a, a_reg, b, b_reg;
(* use_dsp = "yes" *) logic signed [47:0] mult;
logic signed [47:0] post_adder, c;
logic signed [47:0] integrator;

always_comb begin
    case(calculation_counter)
    2'b00:   b = $signed(Ki);
    2'b01:   b = $signed(Kp);
    default: b = $signed(Ki);
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

// Output piplining
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