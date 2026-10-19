// Bit-exact reference model of mac_fir (symmetric FIR on a single DSP).
//
// IN_W/IN_FR   - DATA_WIDTH/FRACT_WIDTH of s_axis
// OUT_W/OUT_FR - DATA_WIDTH/FRACT_WIDTH of m_axis
// Coefficients: bpsk_modem_pkg::FIR_COEFF (first half of the symmetric set, as in
// fir_coeff_mem.sv: if the two lists differ, the testbench reports it).
//
// One output per input sample; the shift register is cleared by reset, so every
// output is checked. Valid while the input period is >= 12 clocks
// (the state machine needs that long per sample).
package mac_fir_model_pkg;

    import bpsk_modem_pkg::*;

    class mac_fir_model #(int IN_W = 16, int IN_FR = 14, int OUT_W = 16, int OUT_FR = 14)
        extends tb_pkg::axis_model #(IN_W, 0, OUT_W, 0);

        localparam int COEFF_NUM  = FIR_COEFF_NUM;
        localparam int HALF       = (COEFF_NUM - 1) / 2;                  // index of the centre tap
        localparam int NORM_SHIFT = IN_FR + (FIR_COEFF_WIDTH - 2) - OUT_FR;

        // 18-bit signed pre-adder register
        local function longint wrap18(longint x);
            logic signed [17:0] t = x[17:0];
            return longint'(t);
        endfunction

        // x[k-j]; zero before the first sample (shift register is cleared by reset)
        local function longint tap(int k, int j);
            return (k - j >= 0) ? in_re(k - j) : 0;
        endfunction

        virtual function void predict();
            longint acc;
            for (int k = 0; k < n_in(); k++) begin
                acc = 0;
                // PAIRS: coeff[i] * (x[i] + x[COEFF_NUM-1-i])
                for (int i = 0; i < HALF; i++)
                    acc += longint'(FIR_COEFF[i]) * wrap18(tap(k, i) + tap(k, COEFF_NUM-1-i));
                // CENTER
                acc += longint'(FIR_COEFF[HALF]) * wrap18(tap(k, HALF));
                put(acc >>> NORM_SHIFT);
            end
        endfunction

    endclass

endpackage
