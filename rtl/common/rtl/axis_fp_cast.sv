//////////////////////////////////////////////////////////////////////////////////
// Module: axis_fp_cast
// Description:
//   Reusable signed fixed-point width/format adapter between two axis_if
// interfaces. Converts s_axis.data (Qm.f, real only) into m_axis.data by
// sign-extending to an intermediate width, shifting by the difference in
// FRACT_WIDTH to reposition the binary point, and truncating to the target
// width. No rounding - if SHIFT < 0 (target has fewer fractional bits),
// the discarded low bits are simply dropped (truncation towards -inf via
// arithmetic right shift), not rounded to nearest.
//////////////////////////////////////////////////////////////////////////////////

module axis_fp_cast #(
    parameter REGISTERED = 1
) (
    input  logic clk,
    input  logic rst,

    axis_if.slave  s_axis, 
    axis_if.master m_axis 
);

localparam int S_W   = s_axis.DATA_WIDTH;
localparam int M_W   = m_axis.DATA_WIDTH;
localparam int SHIFT = m_axis.FRACT_WIDTH - s_axis.FRACT_WIDTH;

initial begin
    if (s_axis.COMPLEX != 0 || m_axis.COMPLEX != 0)
        $fatal(1, "axis_fp_cast: only real (COMPLEX=0) axis_if is supported");
end

// Signed conversion from the s_axis format to the m_axis 
// format: sign extension to an intermediate width, shifting by 
// the difference in FRACT_WIDTH, and truncation to the target width.
function automatic logic signed [M_W-1:0] rescale(input logic signed [S_W-1:0] v);
    logic signed [63:0] wide;
    begin
        wide    = 64'(v);
        wide    = (SHIFT >= 0) ? (wide <<< SHIFT) : (wide >>> -SHIFT);
        rescale = wide[M_W-1:0];
    end
endfunction

logic [M_W-1:0] data_rescaled;
assign data_rescaled = rescale(s_axis.data);

generate
if (REGISTERED) begin : g_registered

    always_ff @(posedge clk) begin
        if (rst) m_axis.valid <= 1'b0;
        else     m_axis.valid <= s_axis.valid;
    end

    always_ff @(posedge clk) begin
        m_axis.data <= data_rescaled;
        m_axis.last <= s_axis.last;
    end

    assign s_axis.ready = m_axis.ready;

end else begin : g_combinational

    assign m_axis.data  = data_rescaled;
    assign m_axis.valid = s_axis.valid;
    assign m_axis.last  = s_axis.last;
    assign s_axis.ready = m_axis.ready;

end
endgenerate

endmodule