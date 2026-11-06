// =============================================================================
// CORDIC: rotation / vectoring mode
//
// Phase format: 2^PHASE_WIDTH == 2*pi (two's complement turns), 0x4000 = +90deg
//
// ROTATIONAL = 1 (rotation mode)
//     (X_out, Y_out) = (X_in, Y_in) * exp(-j*phase_in)     [as in the original]
//     error          = residual angle (~0)
//
// ROTATIONAL = 0 (vectoring mode, magnitude / phase estimator)
//     X_out = |X_in + j*Y_in|    (unsigned, always >= 0)
//     Y_out ~ 0                  (residual)
//     error = atan2(Y_in, X_in)  (signed phase, 2^PHASE_WIDTH == 2*pi)
//     phase_in is ignored
//
// Outputs are DATA_WIDTH+2 bits wide (2 guard bits: sqrt(2) input growth * K).
// Latency (clocks from input valid to output valid):
//     PIPLINED = 1 : STAGES + 2
//     PIPLINED = 0 : STAGES + 3, new input must not come earlier than
//                    STAGES + 1 clocks after the previous one (it is dropped)
//
// !!! Important !!! 
// CORDIC affects output magnitude, so the output signal should be multiplied 
// by 1/K (K = CORDIC gain ~1.6468). This must be taken into account in the 
// next block.
// =============================================================================

module cordic #(
    parameter STAGES = 4,
    parameter DATA_WIDTH = 16,
    parameter PHASE_WIDTH = 16,
    parameter PIPLINED = 1,
    parameter ROTATIONAL = 0
) (
    input logic clk,
    input logic rst,

    input  logic [DATA_WIDTH-1:0]  X_in,
    input  logic [DATA_WIDTH-1:0]  Y_in,
    output logic [DATA_WIDTH+1:0]  X_out,
    output logic [DATA_WIDTH+1:0]  Y_out,
    output logic                   valid,
    output logic [PHASE_WIDTH-1:0] error,           // estimated phase in the vectoring mode
    input  logic [PHASE_WIDTH-1:0] phase_in,        // rotation: angle, vectoring: unused
    input  logic                   phase_valid_in
);

////////////
// Params //
////////////
localparam W  = DATA_WIDTH + 2;               // internal data width
localparam real PI = 3.141592653589793;

typedef struct packed {
    logic signed [W-1:0]           x;
    logic signed [W-1:0]           y;
    logic signed [PHASE_WIDTH-1:0] z;
} state_t;

//////////////////////////////////////////////////////////
// atan(2^-i) table, angle units: 2^PHASE_WIDTH == 2*pi //
//////////////////////////////////////////////////////////
logic signed [PHASE_WIDTH-1:0] atan [0:STAGES-1];
initial begin
    for (int i = 0; i < STAGES; i++)
        atan[i] = PHASE_WIDTH'($rtoi(($atan($pow(2.0, -i)) / (2.0 * PI)) * $pow(2.0, PHASE_WIDTH) + 0.5));
end

////////////////////////
// One micro-rotation //
////////////////////////
function automatic state_t step(input state_t s, input int i);
    state_t r;
    logic   cw;     // clockwise micro-rotation
    cw = (ROTATIONAL != 0) ? ~s.z[PHASE_WIDTH-1] : ~s.y[W-1];
    if (cw) begin
        r.x = s.x + (s.y >>> i);
        r.y = s.y - (s.x >>> i);
    end else begin
        r.x = s.x - (s.y >>> i);
        r.y = s.y + (s.x >>> i);
    end
    // rotation: z -> 0;  vectoring: z accumulates the angle of the vector
    if ((ROTATIONAL != 0) == cw) r.z = s.z - atan[i];
    else                         r.z = s.z + atan[i];
    return r;
endfunction

/////////////////
// Input stage //
/////////////////
// 
// Quadrant pre-rotation by pi, everything in ONE register,
// so x, y, z and valid are always aligned.
//   rotation : phase in [-pi, pi) -> phase - pi when |phase| > pi/2, negate x,y
//   vectoring: x < 0 -> negate x,y, start angle = pi
state_t in_reg;
logic   in_valid;

logic                          flip;
logic signed [PHASE_WIDTH-1:0] z0;
logic signed [W-1:0]           x_ext, y_ext;

assign x_ext = W'($signed(X_in));
assign y_ext = W'($signed(Y_in));

always_comb begin
    if (ROTATIONAL != 0) begin
        flip = phase_in[PHASE_WIDTH-1] ^ phase_in[PHASE_WIDTH-2];
        z0   = {phase_in[PHASE_WIDTH-2], phase_in[PHASE_WIDTH-2:0]};
    end else begin
        flip = X_in[DATA_WIDTH-1];
        z0   = flip ? {1'b1, {(PHASE_WIDTH-1){1'b0}}} : '0;   // pi
    end
end

always_ff @(posedge clk) begin
    if (rst) in_valid <= 1'b0;
    else     in_valid <= phase_valid_in;

    in_reg.x <= flip ? -x_ext : x_ext;
    in_reg.y <= flip ? -y_ext : y_ext;
    in_reg.z <= z0;
end

//////////
// Core //
//////////
state_t fin;
logic   fin_valid;

generate
    if (PIPLINED) begin : CORDIC_pipe

        state_t            pipe  [0:STAGES];
        logic [STAGES-1:0] vreg;      // vreg[i] is aligned with pipe[i+1]

        assign pipe[0] = in_reg;

        always_ff @(posedge clk) begin
            for (int i = 0; i < STAGES; i++)
                pipe[i+1] <= step(pipe[i], i);
        end

        always_ff @(posedge clk) begin
            if (rst) vreg <= '0;
            else begin
                vreg[0] <= in_valid;
                for (int i = 1; i < STAGES; i++) vreg[i] <= vreg[i-1];
            end
        end

        assign fin       = pipe[STAGES];
        assign fin_valid = vreg[STAGES-1];

    end else begin : CORDIC_iter

        state_t                    it;
        logic [$clog2(STAGES+1)-1:0] it_cnt;
        logic                      it_busy;
        logic                      it_valid;

        always_ff @(posedge clk) begin
            if (rst) begin
                it_cnt   <= '0;
                it_busy  <= 1'b0;
                it_valid <= 1'b0;
            end else begin
                it_valid <= 1'b0;
                if (!it_busy) begin
                    if (in_valid) begin
                        it      <= in_reg;
                        it_cnt  <= '0;
                        it_busy <= 1'b1;
                    end
                end else begin
                    it <= step(it, int'(it_cnt));
                    if (it_cnt == STAGES-1) begin
                        it_busy  <= 1'b0;
                        it_valid <= 1'b1;
                        it_cnt   <= '0;
                    end else begin
                        it_cnt <= it_cnt + 1'b1;
                    end
                end
            end
        end

        assign fin       = it;
        assign fin_valid = it_valid;

    end
endgenerate

//////////////////
// Output stage //
//////////////////
always_ff @(posedge clk) begin
    if (rst) valid <= 1'b0;
    else     valid <= fin_valid;

    if (fin_valid) begin
        X_out <= fin.x;
        Y_out <= fin.y;
        error <= fin.z;
    end
end

endmodule