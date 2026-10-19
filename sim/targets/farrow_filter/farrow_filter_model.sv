// Bit-exact reference model of farrow_filter_fixed.sv + horner_mac (used by farrow_filter_tb).
//
// W           - DATA_WIDTH of one component (Re or Im)
// CPLX        - 1: complex stream, Re and Im are processed by two identical,
//               independent filters (assumed structure of farrow_cplx_wrap)
// DELAY_WIDTH - DELAY_WIDTH parameter of the RTL
//
// Valid only while the input sample period is long enough for the single-DSP
// Horner scheme to finish: >= 11 clocks per sample (checked against the RTL;
// at 9 clocks the RTL itself loses outputs). Use clk_per_valid >= 12 in the testbench.
package farrow_filter_model;

    class farrow_model #(int W = 16, int CPLX = 0, int DELAY_WIDTH = 16)
        extends tb_pkg::axis_model #(W, CPLX, W, CPLX);

        localparam int unsigned HALF = 2**(DELAY_WIDTH-1);       // 1.0 in the delay format
        localparam int unsigned MASK = 2**DELAY_WIDTH - 1;

        int unsigned delay;     // value the DUT sees on its delay register

        // Same values as on the delay_in / correction_en_in ports
        function new(int unsigned delay_in = 2**(DELAY_WIDTH-2), bit correction_en = 1);
            delay = (correction_en ? delay_in + 2**(DELAY_WIDTH-2) : 2**(DELAY_WIDTH-2)) & MASK;
        endfunction

        // x[k]: input sample k of the Re (im=0) or Im (im=1) channel
        local function longint smp(int k, bit im);
            return im ? in_im(k) : in_re(k);
        endfunction

        // 18-bit signed operand of the DSP multiplier (a = ... assigns to logic signed [17:0])
        local function longint wrap18(longint x);
            logic signed [17:0] t = x[17:0];
            return longint'(t);
        endfunction

        // Coefficient math + Horner scheme with the RTL's truncations.
        // shift_reg[0] is the newest sample x[k], shift_reg[3] the oldest x[k-3].
        local function longint horner(int k, bit im, longint mu);
            longint s0 = smp(k,   im);
            longint s1 = smp(k-1, im);
            longint s2 = smp(k-2, im);
            longint s3 = smp(k-3, im);
            longint d1 = (s2 - s0) >>> 1;
            longint d2 = (s3 - s1) >>> 1;
            longint dl =  s2 - s1;
            longint c0 = s1;
            longint c1 = d1;
            longint c2 =  3*dl - (2*d1 + d2);
            longint c3 = -2*dl + (d1 + d2);
            longint a, post;

            a    = wrap18(c3);
            post = (c2 <<< (DELAY_WIDTH-1)) + a * mu;
            a    = wrap18(post >>> (DELAY_WIDTH-1));
            post = (c1 <<< (DELAY_WIDTH-1)) + a * mu;
            a    = wrap18(post >>> (DELAY_WIDTH-1));
            post = (c0 <<< (DELAY_WIDTH-1)) + a * mu;
            return post >>> (DELAY_WIDTH-1);
        endfunction

        virtual function void predict();
            int unsigned cnt = 0, nxt, mu = 0;
            for (int k = 0; k < n_in(); k++) begin
                // DelaySeparation: runs once per input sample
                nxt = (cnt + delay) & MASK;
                if (nxt[DELAY_WIDTH-1]) begin
                    // mu from the newer sample of the interval: 2*counter - 1.0, 0 if negative
                    mu  = ((2*cnt) >= HALF) ? ((2*cnt - HALF) & MASK) : 0;
                    cnt = (nxt - HALF) & MASK;
                end else begin
                    cnt = nxt;
                end

                // horner_valid = coeff_ready[3] & calc_flag: calc_flag is NOT delayed in the RTL,
                // 4 clocks later it already shows the decision for the NEXT sample
                // (counter is updated), while mu is the one latched above.
                if ((((cnt + delay) & MASK) >> (DELAY_WIDTH-1)) != 0) begin
                    if (k < 3) begin
                        put_dc();               // shift_reg is not reset: X until 4 samples are in
                    end else if (CPLX) begin
                        put(horner(k, 0, mu), horner(k, 1, mu));
                    end else begin
                        put(horner(k, 0, mu));
                    end
                end
            end
        endfunction

    endclass

endpackage
