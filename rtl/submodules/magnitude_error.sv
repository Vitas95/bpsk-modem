module magnitude_error #(
    parameter STAGES
)(
    input  logic    clk,
    input  logic    rst,
    axis_if.slave   s_axis,
    axis_if.master  m_axis
);
    localparam int E = $bits(error.data);   // error with must be >= ampl.DATA_WIDTH + 1

    // Taking into account CORDIC gain
    function automatic real calc_gain(input int n);
        real k;
        k = 1.0;
        for (int i = 0; i < n; i++) k = k * $sqrt(1.0 + 2.0 ** (-2.0 * i));
        return k;
    endfunction

    // Reference value is 1.0 with CORDIC gain
    logic [E-1:0] reference = $rtoi($pow(2.0, s_axis.FRACT_WIDTH) * calc_gain(STAGES) + 0.5);

    always_ff @(posedge clk) begin
        if (rst) m_axis.valid <= 1'b0;
        else begin
            m_axis.valid <= s_axis.valid;
            m_axis.data  <= reference - E'(s_axis.data);
        end
    end
endmodule