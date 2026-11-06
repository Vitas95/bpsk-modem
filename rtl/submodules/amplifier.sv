`include "axis_checks.svh"

// Complex amplifier for an AGC loop on a single DSP48A1
//   m_axis = s_axis * gain,   (re + j*im) * g = re*g + j*im*g

module amplifier (
    input logic clk,
    input logic rst,

    axis_if.slave  s_axis,
    axis_if.slave  gain,
    axis_if.master m_axis
);

`CHECK_COMPLEX_FIELD(s_axis, 1)
`CHECK_COMPLEX_FIELD(gain, 0)
`CHECK_COMPLEX_FIELD(m_axis, 1)

////////////
// Params //
////////////
localparam int WI = s_axis.DATA_WIDTH;   localparam int FI = s_axis.FRACT_WIDTH;
localparam int WG = gain.DATA_WIDTH;     localparam int FG = gain.FRACT_WIDTH;
localparam int WO = m_axis.DATA_WIDTH;   localparam int FO = m_axis.FRACT_WIDTH;

localparam int WP    = WI + WG + 1;             // product width (gain is zero-extended by 1 bit)
localparam int FP    = FI + FG;                 // product binary point
localparam int SH_R  = (FP > FO) ? FP - FO : 0; // right shift
localparam int SH_L  = (FO > FP) ? FO - FP : 0; // left shift
localparam int WE_0  = WP + SH_L + 1;
localparam int WE    = (WE_0 > WO + 1) ? WE_0 : WO + 1;  // working width

localparam logic signed [WE-1:0] RND = (SH_R > 0) ? (WE'(1) <<< (SH_R - 1)) : '0;
localparam logic signed [WE-1:0] MAX =  (WE'(1) <<< (WO - 1)) - 1;
localparam logic signed [WE-1:0] MIN = -(WE'(1) <<< (WO - 1));

////////////
// Checks //
////////////

if (WI > 18) begin : InWidthCheck
    $error("amplifier: s_axis DATA_WIDTH must be <= 18 (DSP48A1 multiplier input)");
end

if (WG > 17) begin : GainWidthCheck
    $error("amplifier: gain DATA_WIDTH must be <= 17 (unsigned gain + sign bit for DSP48A1)");
end

////////////////////////////// 
// shift + round + saturate //
//////////////////////////////
function automatic logic signed [WO-1:0] fit (input logic signed [WP-1:0] x);
    logic signed [WE-1:0] t;
    t = ((WE'(x) <<< SH_L) + RND) >>> SH_R;
    if      (t > MAX) return MAX[WO-1:0];
    else if (t < MIN) return MIN[WO-1:0];
    else              return t[WO-1:0];
endfunction

////////////////////
// Hold registers //
////////////////////
logic signed [WI-1:0] hold_re, hold_im;
logic        [WG-1:0] hold_g;
logic                 s_flag, g_flag;

logic work_v;       // work registers contain a pair, it is issued to the DSP
logic sel;          // 0 - re is issued to the DSP, 1 - im is issued
logic start;

// Start when both samples are here and the work registers are free
// (empty or are emptied right now)
assign start = s_flag & g_flag & (!work_v | sel);

always_ff @(posedge clk) begin : HoldReg
    if (rst) begin
        hold_re <= '0;
        hold_im <= '0;
        hold_g  <= '0;
        s_flag  <= 1'b0;
        g_flag  <= 1'b1;    // Pass first gain value without valid
    end else begin
        // Pair is taken to the work registers, new sample below has priority
        if (start) begin
            s_flag <= 1'b0;
            g_flag <= 1'b0;
        end

        if (s_axis.valid) begin
            hold_re <= s_axis.data[WI-1:0];
            hold_im <= s_axis.data[2*WI-1:WI];
            s_flag  <= 1'b1;
        end

        if (gain.valid) begin
            hold_g <= gain.data;
            g_flag <= 1'b1;
        end
    end
end

////////////////////
// Work registers //
////////////////////

// The operands must stay stable while both components are issued to the DSP.
logic signed [WI-1:0] work_re, work_im;
logic        [WG-1:0] work_g;

always_ff @(posedge clk) begin : WorkReg
    if (rst) begin
        work_v <= 1'b0;
        sel    <= 1'b0;
    end else begin
        if (start)     work_v <= 1'b1;
        else if (sel)  work_v <= 1'b0;

        if (work_v) sel <= ~sel;
    end
end

always_ff @(posedge clk) begin : WorkData
    if (start) begin
        work_re <= hold_re;
        work_im <= hold_im;
        work_g  <= hold_g;
    end
end

/////////////////////////////////
// Single DSP48A1 (behavioral) //
/////////////////////////////////
logic signed [17:0] a_reg, b_reg;
(* use_dsp = "yes" *) logic signed [35:0] m_reg;
logic signed [47:0] p_reg;

always_ff @(posedge clk) begin : DspPipeline
    a_reg <= sel ? work_im : work_re;
    b_reg <= signed'(18'(work_g));  // unsigned gain -> positive signed
    m_reg <= a_reg * b_reg;
    p_reg <= m_reg;
end

// Tag pipeline, one stage per DSP register
logic v1, v2, v3;
logic im1, im2, im3;       // the stage holds the im component

always_ff @(posedge clk) begin : TagPipeline
    if (rst) begin
        v1 <= 1'b0;
        v2 <= 1'b0;
        v3 <= 1'b0;
    end else begin
        v1 <= work_v;
        v2 <= v1;
        v3 <= v2;
    end
end

always_ff @(posedge clk) begin : TagData
    im1 <= sel;
    im2 <= im1;
    im3 <= im2;
end

////////////
// Output //
////////////
logic signed [WO-1:0] re_fit;

always_ff @(posedge clk) begin : Output
    if (rst) m_axis.valid <= 1'b0;
    else     m_axis.valid <= v3 && im3;

    if (v3) begin
        if (!im3) re_fit       <= fit(p_reg[WP-1:0]);
        else      m_axis.data  <= {fit(p_reg[WP-1:0]), re_fit};
    end
end

endmodule