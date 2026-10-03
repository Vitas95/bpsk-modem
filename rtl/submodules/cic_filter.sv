module cic_filter #(
    parameter UPSAMPLING = 20,
    parameter STAGES = 4,
    parameter DIFF_DELAY = 1,
    parameter DECIMATE = 0  // 0 - interpolation, 1 - decimation
) (
    input logic clk,
    input logic rst,

    axis_if.slave s_axis,
    axis_if.master m_axis
);

localparam OUTPUT_WIDTH = s_axis.DATA_WIDTH + STAGES * $clog2(UPSAMPLING * DIFF_DELAY);
localparam NORM_SHIFT = DECIMATE ? $clog2((UPSAMPLING * DIFF_DELAY) ** STAGES)
                                 : $clog2(((UPSAMPLING * DIFF_DELAY) ** STAGES) / UPSAMPLING);

`define _COMB_STAGE(name, data_input, data_output, valid_sig)\
    comb #(                                 \
    .DATA_WIDTH_IN($bits(data_input)),      \
    .DATA_WIDTH_OUT($bits(data_output)),    \
    .DIFF_DELAY(DIFF_DELAY)                 \
    ) ``name`` (                            \
    .clk(clk),                              \
    .rst(rst),                              \
    .data_in(``data_input``),               \
    .valid_in(``valid_sig``),               \
    .data_out(``data_output``)              \
    );

`define _INT_STAGE(name, data_input, data_output, valid_sig) \
    integrator #(                           \
        .DATA_WIDTH_IN($bits(data_input)),  \
        .DATA_WIDTH_OUT($bits(data_output)) \
    ) ``name`` (                            \
        .clk(clk),                          \
        .rst(rst),                          \
        .data_in(``data_input``),           \
        .valid_in(``valid_sig``),           \
        .data_out(``data_output``)          \
    );

genvar i;

generate
if (!DECIMATE) begin : g_interpolator
    // ---------------------------------------------------------------
    // Comb stages.
    // ---------------------------------------------------------------
    localparam int COMB_WIDTH = s_axis.DATA_WIDTH + STAGES;
    logic signed [COMB_WIDTH - 1 :0] comb_data [1:STAGES];

    for (i = 0; i < STAGES; i = i + 1) begin : comb_gen
        localparam int W_IN  = s_axis.DATA_WIDTH + i;
        localparam int W_OUT = (s_axis.DATA_WIDTH + i + 1);

        if (i == 0) begin : g_first
            `_COMB_STAGE(u_comb, s_axis.data, comb_data[i+1][W_OUT-1:0], s_axis.valid)
        end else begin : g_rest
            `_COMB_STAGE(u_comb, comb_data[i][W_IN-1:0], comb_data[i+1][W_OUT-1:0], s_axis.valid)
        end
    end

    // ---------------------------------------------------------------
    // Upsampling. Zero-stuffing.
    // ---------------------------------------------------------------
    logic signed [COMB_WIDTH - 1 : 0] upsampled;

    always_ff @( posedge clk ) begin : upsampling
        if (s_axis.valid)
            upsampled <= comb_data[STAGES];
        else
            upsampled <= '0;
    end

    // ---------------------------------------------------------------
    // Integrator stages.
    // ---------------------------------------------------------------
    localparam int TOTAL_GROWTH     = OUTPUT_WIDTH - COMB_WIDTH;
    localparam int GROWTH_PER_STAGE = (TOTAL_GROWTH + STAGES - 1) / STAGES; // ceil

    logic signed [OUTPUT_WIDTH-1:0] int_data [0:STAGES];
    assign int_data[0][OUTPUT_WIDTH-1:0] = $signed(upsampled);

    for (i = 0; i < STAGES; i = i + 1) begin : int_gen
        localparam int W_IN_RAW  = COMB_WIDTH + i     * GROWTH_PER_STAGE;
        localparam int W_OUT_RAW = COMB_WIDTH + (i+1) * GROWTH_PER_STAGE;

        localparam int W_IN  = (i == 0)        ? COMB_WIDTH  :
                               (W_IN_RAW  > OUTPUT_WIDTH) ? OUTPUT_WIDTH : W_IN_RAW;
        localparam int W_OUT = (i == STAGES-1) ? OUTPUT_WIDTH :
                                (W_OUT_RAW > OUTPUT_WIDTH) ? OUTPUT_WIDTH : W_OUT_RAW;
         
        `_INT_STAGE(u_int, int_data[i][W_IN-1:0], int_data[i+1][W_OUT-1:0], s_axis.valid)
    end

    // Output pipline and normalisation
    logic [m_axis.DATA_WIDTH-1:0] norm_data;
    assign norm_data = int_data[STAGES] >>> (NORM_SHIFT - (m_axis.FRACT_WIDTH - s_axis.FRACT_WIDTH));

    always_ff @( posedge clk ) begin : OutPipline
        if (rst) m_axis.valid <= 0;
        else m_axis.valid <= 1;
        m_axis.data <= norm_data;
    end

end else begin : g_decimator
    logic signed [s_axis.DATA_WIDTH-1:0] gated_in;

    always_ff @( posedge clk ) begin : input_gating
        if (s_axis.valid)
            gated_in <= $signed(s_axis.data);
        else
            gated_in <= '0;
    end

    // ---------------------------------------------------------------
    // Integrator stages.
    // ---------------------------------------------------------------

    logic signed [OUTPUT_WIDTH-1:0] int_data [0:STAGES];
    assign int_data[0][OUTPUT_WIDTH-1:0] = $signed(gated_in); 

    for (i = 0; i < STAGES; i = i + 1) begin : int_gen
        `_INT_STAGE(u_int, int_data[i][OUTPUT_WIDTH-1:0], int_data[i+1][OUTPUT_WIDTH-1:0], s_axis.valid)
    end

    // ---------------------------------------------------------------
    // Decimation
    // ---------------------------------------------------------------
    localparam int CNT_WIDTH = (UPSAMPLING > 1) ? $clog2(UPSAMPLING) : 1;
    logic [CNT_WIDTH-1:0]           dec_cnt;
    logic                           dec_valid;
    logic signed [OUTPUT_WIDTH-1:0] decimated;

    always_ff @( posedge clk ) begin : decimation
        if (rst) begin
            dec_cnt   <= '0;
            dec_valid <= 1'b0;
        end else if (s_axis.valid) begin
            if (dec_cnt == UPSAMPLING - 1) begin
                dec_cnt   <= '0;
                dec_valid <= 1'b1;
                decimated <= int_data[STAGES];
            end else begin
                dec_cnt   <= dec_cnt + 1'b1;
                dec_valid <= 1'b0;
            end
        end else begin
            dec_valid <= 1'b0;
        end
    end

    // Comb
    logic signed [OUTPUT_WIDTH-1:0] comb_data [0:STAGES];
    assign comb_data[0] = decimated;

    for (i = 0; i < STAGES; i = i + 1) begin : comb_gen
        `_COMB_STAGE(u_comb, comb_data[i], comb_data[i+1], dec_valid)
    end

    // Output pipline and normalisation
    logic [m_axis.DATA_WIDTH-1:0] norm_data;
    assign norm_data = comb_data[STAGES] >>> (NORM_SHIFT - (m_axis.FRACT_WIDTH - s_axis.FRACT_WIDTH));

    always_ff @( posedge clk ) begin : OutPipline
        if (rst) m_axis.valid <= 0;
        else     m_axis.valid <= dec_valid;
        m_axis.data <= norm_data;
    end
end
endgenerate

`undef _COMB_STAGE
`undef _INT_STAGE

endmodule