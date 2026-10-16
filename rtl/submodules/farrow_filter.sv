module farrow_filter #(
    parameter DELAY_WIDTH   = 16
) (
    input logic clk,
    input logic rst,

    axis_if.slave s_axis,
    axis_if.master m_axis,

    input logic [DELAY_WIDTH-1:0] delay_in,
    input logic                   correction_en_in
);

// Input pipline
logic                   correction_en, valid;
logic [DELAY_WIDTH-1:0] delay;

always_ff @(posedge clk) begin : InPipeline
    if(rst) begin
        valid         <= 0;
        correction_en <= 0;
    end else begin
        valid         <= s_axis.valid;
        correction_en <= correction_en_in;
    end

    if  (correction_en) delay <= delay_in;
    else                delay <= 2**(DELAY_WIDTH-2);
end

// Sample counter math
// We have input delay bus with a simple format:
// First bit - integer part; Other bits - fractional part

logic [DELAY_WIDTH-1:0] counter, next_counter, mu;
logic                   calc_flag;

always_comb begin
    next_counter = counter + delay;
    calc_flag = next_counter[DELAY_WIDTH-1];
end

always_ff @(posedge clk) begin : DelaySeparation
    if (rst) begin
        mu           <= '0;
        counter      <= '0;
    end else begin
        mu           <= mu;
        counter      <= counter;
        if (valid) begin
            if (calc_flag) begin
                counter <= next_counter - 2**(DELAY_WIDTH-1);
                mu      <= (2**(DELAY_WIDTH-1) - counter) <<< 1;
            end else begin
                counter <= next_counter;
            end
        end
    end
end

// Sample shift register
// We always pass the data through this register.
// The rest math depends on the input delay constant
localparam DATA_WIDTH = s_axis.DATA_WIDTH;
logic signed [DATA_WIDTH+4:0] shift_reg [0:3];

always_ff @(posedge clk) begin : ShiftReg
    if (valid) begin
        for (int i = 0; i < 4; i++) begin
            if (i == 0) shift_reg[0] <= $signed(s_axis.data);
            else        shift_reg[i] <= shift_reg[i-1];
        end
    end else begin
        shift_reg <= shift_reg;
    end
end

// Math of this filter is based on a Horner scheme which rely on a
// 4 samples window. Furher coefficient calculations will be explained.
// First step is a derivalive calculation: 
//  d1 = 0.5 * (x2 - x0); 
//  d2 = 0.5 * (x3 - x1);
// Next calculating intermediate delta for further calculations:
//  delta = x2 - x1;
// Then calculating polynomial coefficients:
//  c0 = x1;
//  c1 = d1;
//  c2 =  3 * delta - 2*d1 - d2;
//  c3 = -2 * delta +   d1 + d2;

localparam COEFF_DELAY = 4;
logic signed [DATA_WIDTH+4:0] d1, d2, delta;
always_ff @(posedge clk) begin
    d1    <= $signed(shift_reg[2] - shift_reg[0]) >>> 1;
    d2    <= $signed(shift_reg[3] - shift_reg[1]) >>> 1;
    delta <=  shift_reg[2] - shift_reg[1];
end

logic signed [DATA_WIDTH+4:0]   c0, c1, c2, c3,
                                c2_part1, c2_part2,
                                c3_part1;
always_ff @(posedge clk) begin
    c0       <= shift_reg[1];
    c1       <=           d1;
    c2_part1 <=  (delta <<< 1) + delta;
    c2_part2 <=     (d1 <<< 1) + d2;
    c2       <=     c2_part1  - c2_part2;
    c3_part1 <=           d1  + d2;
    c3       <= -(delta <<< 1) + c3_part1;
end

// Valid delay for dealyed start of a Horner's method 
// with a single DSP.
logic [3:0] coeff_ready;
always_ff @(posedge clk) begin
    coeff_ready <= {coeff_ready[2:0],valid};
end

logic horner_valid;
assign horner_valid = coeff_ready[3] & calc_flag;

horner_mac #(
    .DATA_WIDTH(DATA_WIDTH),
    .MU_WIDTH(DELAY_WIDTH)
) horner_mac_inst (
    .clk(clk),
    .rst(rst),

    .valid_in(horner_valid),
    .c0(c0), .c1(c1), .c2(c2), .c3(c3),
    .mu(mu),

    .data_out(m_axis.data),
    .valid_out(m_axis.valid)
);

endmodule