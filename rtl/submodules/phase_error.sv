`include "axis_checks.svh"
module phase_error (
    input  logic    clk,
    input  logic    rst,
    axis_if.slave   s_axis,
    axis_if.master  m_axis
);

`CHECK_COMPLEX_FIELD(s_axis, 1)

localparam int W = s_axis.DATA_WIDTH;  // width of one component, data is packed as {imag, real}
localparam int E = m_axis.DATA_WIDTH;  // error width must be >= W + 1

// BPSK phase error is imag * sign(real)
 
always_ff @(posedge clk) begin
    if (rst) m_axis.valid <= 1'b0;
    else begin
        m_axis.valid <= s_axis.valid;
        m_axis.data  <= s_axis.data[W-1] ? -E'($signed(s_axis.data[2*W-1:W]))
                                         :  E'($signed(s_axis.data[2*W-1:W]));
    end
end
endmodule