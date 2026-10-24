module digital_converter #(
    parameter EXP_WIDTH       = 15,
    parameter PHASE_WIDTH     = 16,
    parameter DOWN_CONVERSION = 0
) (
    input clk,
    input rst,

    axis_if.slave s_axis,
    axis_if.master m_axis
);

// Sine and cosine have only a fractional part and a sign as a MSB
logic signed [EXP_WIDTH - 1 : 0] sin_out, cos_out;
exp_lut #(            
    .EXP_WIDTH(EXP_WIDTH),   
    .PHASE_WIDTH(PHASE_WIDTH)
) exp_lut_inst (      
    .clk(clk),        
    .rst(rst),        
    .sin_out(sin_out),    
    .cos_out(cos_out)     
);

// Generating module with multiplier behavioral DSP48A1
generate
    if (DOWN_CONVERSION == 1) begin 

        (* use_dsp = "yes" *) // REWRITE!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        logic signed [17:0] dsp_a_0, dsp_b_0, dsp_a_1, dsp_b_1;
        logic signed [47:0] dsp_p_0, dsp_p_1;

        logic signed [m_axis.DATA_WIDTH-1:0] real_out, imag_out;

        // Module after ADC with a real output and a complex output
        always_ff @(posedge clk) begin
            dsp_a_0 <= cos_out;
            dsp_b_0 <= $signed(s_axis.data);
            dsp_a_1 <= sin_out;
            dsp_b_1 <= $signed(s_axis.data);

            real_out <= dsp_p_0 >>> s_axis.FRACT_WIDTH;
            imag_out <= (-dsp_p_1) >>> s_axis.FRACT_WIDTH;

            if (rst) begin
                m_axis.data  <= '0;
                m_axis.valid <=  0;
            end else begin  
                m_axis.data  <= {imag_out, real_out};
                m_axis.valid <= 1;
            end
        end

        // Multiplication in DSP always work
        always_ff @(posedge clk) begin
            dsp_p_0 <= dsp_a_0 * dsp_b_0;
            dsp_p_1 <= dsp_a_1 * dsp_b_1;
        end

    end else if ((DOWN_CONVERSION == 0) && s_axis.COMPLEX) begin
        // Module before DAC with a complex input and a real output
        (* use_dsp = "yes" *) 
        logic signed [17:0] dsp_a_0, dsp_b_0, dsp_a_1, dsp_b_1;
        logic signed [47:0] dsp_p_0, dsp_p_1;
        logic signed [47:0] post_adder;

        localparam DATA_W = s_axis.DATA_WIDTH;
        localparam SHIFT = s_axis.FRACT_WIDTH + (EXP_WIDTH-1) - m_axis.FRACT_WIDTH;

        always_ff @(posedge clk) begin
            dsp_a_0 <= sin_out;
            dsp_a_1 <= cos_out;
            dsp_b_0 <= $signed(s_axis.data[DATA_W*2 - 1:DATA_W]);
            dsp_b_1 <= $signed(s_axis.data[DATA_W-1 : 0]);

            post_adder <= dsp_p_0 - dsp_p_1;

            if (rst) begin
                m_axis.data  <= '0;
                m_axis.valid <=  0;
            end else begin  
                m_axis.data  <= post_adder >>> SHIFT;
                m_axis.valid <= 1;
            end
        end

        // Multiplication in DSP always work
        always_ff @(posedge clk) begin
            dsp_p_0 <= dsp_a_0 * dsp_b_0;
            dsp_p_1 <= dsp_a_1 * dsp_b_1;
        end

    end else begin 
        // Module before DAC with a real input and a real output
        (* use_dsp = "yes" *) 
        logic signed [17:0] dsp_a_0, dsp_b_0;
        logic signed [47:0] dsp_p_0;

        localparam SHIFT = s_axis.FRACT_WIDTH + (EXP_WIDTH-1) - m_axis.FRACT_WIDTH;

        always_ff @(posedge clk) begin
            dsp_a_0 <= sin_out;
            dsp_b_0 <= $signed(s_axis.data);

            if (rst) begin
                m_axis.data  <= '0;
                m_axis.valid <=  0;
            end else begin  
                m_axis.data  <= dsp_p_0 >>> SHIFT;
                m_axis.valid <= 1;
            end
        end

        // Multiplication in DSP always work
        always_ff @(posedge clk) begin
            dsp_p_0 <= dsp_a_0 * dsp_b_0;
        end
    end
endgenerate 

endmodule