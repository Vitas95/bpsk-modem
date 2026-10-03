module cordic_top #(
    parameter STAGES = 4,
    parameter DATA_WIDTH = 16,
    parameter PHASE_WIDTH = 16,
    parameter PIPLINED = 1
) (
    input clk,
    input rst,

    input  logic [DATA_WIDTH-1:0]  X_in,
    input  logic [DATA_WIDTH-1:0]  Y_in,
    output logic [DATA_WIDTH-1:0]  X_out,
    output logic [DATA_WIDTH-1:0]  Y_out,
    output logic                   valid,
    output logic [PHASE_WIDTH-1:0] error,
    input  logic [PHASE_WIDTH-1:0] phase_in,
    input  logic                   phase_valid_in
);

// Local parameters
localparam COUNT_WIDTH = $clog2(STAGES);
localparam real PI = 3.141592653589793;

// Delay is a sum of stages delay, input pipline delay 
// and a phase wrap delay
localparam VALID_DELAY = STAGES + 2;

    
logic signed [PHASE_WIDTH-1:0] phase;
logic                          phase_valid;
typedef struct packed {
    logic signed [DATA_WIDTH-1:0] x;
    logic signed [DATA_WIDTH-1:0] y;
} complex;

complex init;

// Input piplining
always_ff @(posedge clk) begin
    if (rst) phase_valid <= 0;
    else begin 
        phase_valid <= phase_valid_in;
        phase       <= phase_in;
        init.x      <= X_in;
        init.y      <= Y_in;
    end
end

// atan(2^-stage) memory
logic signed [PHASE_WIDTH-1:0] atan [0:STAGES-1];
initial begin
    for (int i = 0; i < STAGES; i++)
        atan[i] = int'(($atan($pow(2,-i)) / PI / 2)*$pow(2,PHASE_WIDTH)); // int limits atan memory up to 32 bits
end

// Theta preprocessing from -pi:pi to -pi/2:pi/2
logic signed [PHASE_WIDTH-1:0] phase_wrapped;
logic second_quad, third_quad, unwrap;
assign second_quad = phase[PHASE_WIDTH-2] & ~phase[PHASE_WIDTH-1];
assign third_quad  = ~phase[PHASE_WIDTH-2] & phase[PHASE_WIDTH-1];
assign unwrap = second_quad | third_quad;

always_ff @(posedge clk) begin
    phase_wrapped <= {phase[PHASE_WIDTH-2], phase[PHASE_WIDTH-2:0]};
end

generate
    
    if (PIPLINED) begin: CORDIC_pipe

        // CORDIC core piplined
        complex                        stage [0:STAGES];
        logic signed [PHASE_WIDTH-1:0] theta [0:STAGES];

        always_ff @(posedge clk) begin
            stage[0] <= init;
            theta[0] <= phase_wrapped;
        end

        // CORDIC
        always_ff @(posedge clk) begin
            for (int i = 0; i < STAGES; i++) begin
                if (~(theta[i][PHASE_WIDTH-1])) begin
                    stage[i+1].x <= stage[i].x + (stage[i].y >>> i);
                    stage[i+1].y <= stage[i].y - (stage[i].x >>> i);
                    theta[i+1]   <= theta[i] - atan[i];
                end else if ((theta[i][PHASE_WIDTH-1])) begin
                    stage[i+1].x <= stage[i].x - (stage[i].y >>> i);
                    stage[i+1].y <= stage[i].y + (stage[i].x >>> i);
                    theta[i+1]   <= theta[i] + atan[i];      
                end
            end    
        end

        // Valid and unwrap signals delay
        logic [VALID_DELAY-1:0] valid_delay, unwrap_delay;
        always_ff @(posedge clk) begin
            if (rst) begin 
                valid_delay  <= {valid_delay[VALID_DELAY-2:0],0};
                unwrap_delay <= {unwrap_delay[VALID_DELAY-2:0],0};
            end else begin
                valid_delay <= {valid_delay[VALID_DELAY-2:0],phase_valid};
                unwrap_delay <= {unwrap_delay[VALID_DELAY-2:0],unwrap};
            end
        end

        // Output piplining
        always_ff @(posedge clk) begin
        valid <= valid_delay[VALID_DELAY-1];
            if (valid_delay[VALID_DELAY-1]) begin
                if (unwrap_delay[VALID_DELAY-1]) begin
                    X_out <= -stage[STAGES].x;
                    Y_out <= -stage[STAGES].y;
                end else begin
                    X_out <= stage[STAGES].x;
                    Y_out <= stage[STAGES].y;
                end
                error <= theta[STAGES-1];
            end 
        end

    end else begin: CORDIC_iter
        // CORDIC iterative
        complex                        iter_stage;
        logic signed [PHASE_WIDTH-1:0] iter_theta;
        logic [$clog2(STAGES)-1:0]     iter_cnt;
        logic                          iter_busy;
        logic                          iter_valid;
        logic                          unwrap_saved;
        logic                          phase_valid_d;

        always_ff @(posedge clk) begin
            // Compensating phase wrap delay
            phase_valid_d <= phase_valid;
        end
        
        always_ff @(posedge clk) begin
        if (rst) begin
            iter_cnt     <= '0;
            iter_busy    <= 1'b0;
            iter_valid   <= 1'b0;
            unwrap_saved <= 1'b0;
        end else begin
            iter_valid <= 1'b0;

            if (!iter_busy & phase_valid_d) begin
                iter_stage   <= init;
                iter_theta   <= phase_wrapped;
                unwrap_saved <= unwrap;
                iter_cnt     <= '0;
                iter_busy    <= 1'b1;
            end else if (iter_busy) begin
                
                // CORDIC
                if (~iter_theta[PHASE_WIDTH-1]) begin
                    iter_stage.x <= iter_stage.x + (iter_stage.y >>> iter_cnt);
                    iter_stage.y <= iter_stage.y - (iter_stage.x >>> iter_cnt);
                    iter_theta   <= iter_theta   - atan[iter_cnt];
                end else begin
                    iter_stage.x <= iter_stage.x - (iter_stage.y >>> iter_cnt);
                    iter_stage.y <= iter_stage.y + (iter_stage.x >>> iter_cnt);
                    iter_theta   <= iter_theta   + atan[iter_cnt];
                end

                if (iter_cnt == STAGES-1) begin
                    iter_busy  <= 1'b0;
                    iter_valid <= 1'b1;
                    iter_cnt   <= 1'b0;
                end else if (~(iter_cnt == STAGES-1) & iter_busy) begin
                    iter_cnt <= iter_cnt + 1'b1;
                end
            end
        end
        end

        // Output piplining
        always_ff @(posedge clk) begin
        valid <= iter_valid;
            if (iter_valid) begin
                if (unwrap_saved) begin
                    X_out <= -iter_stage.x;
                    Y_out <= -iter_stage.y;
                end else begin
                    X_out <= iter_stage.x;
                    Y_out <= iter_stage.y;
                end
                error <= iter_theta;
            end 
        end        
    end

endgenerate

endmodule