// Bit-exact, clock-by-clock reference model of cic_filter (interpolator and decimator).
//
// IN_W/IN_FR   - DATA_WIDTH/FRACT_WIDTH of s_axis
// OUT_W/OUT_FR - DATA_WIDTH/FRACT_WIDTH of m_axis
// UPSAMPLING, STAGES, DIFF_DELAY, DECIMATE - the same parameters as the RTL
//
// The RTL is not a pure function of the input samples (integrators run every clock,
// combs only on valid, the interpolator output is valid on EVERY clock), so the model
// replays the registers clock by clock using the clock numbers of the input transfers
// (axis_model.in_cycle). Interpolator: one output per clock from cycle 0 up to the last
// output the DUT produced. Decimator: one output per dec_valid.
//
// Model state after reset is all zeros; cycle 0 is the first clock edge after env.reset().
package cic_filter_model_pkg;

    class cic_model #(int IN_W = 16, int IN_FR = 14, int OUT_W = 16, int OUT_FR = 14,
                      int UPSAMPLING = 20, int STAGES = 4, int DIFF_DELAY = 1, int DECIMATE = 0)
        extends tb_pkg::axis_model #(IN_W, 0, OUT_W, 0);

        // Same formulas as in cic_filter.sv
        localparam int OW         = IN_W + STAGES * $clog2(UPSAMPLING * DIFF_DELAY);
        localparam int NORM_SHIFT = DECIMATE ? $clog2((UPSAMPLING * DIFF_DELAY) ** STAGES)
                                             : $clog2(((UPSAMPLING * DIFF_DELAY) ** STAGES) / UPSAMPLING);
        localparam int SHIFT      = NORM_SHIFT - (OUT_FR - IN_FR);
        localparam int COMB_W     = IN_W + STAGES;
        localparam int GROWTH     = ((OW - COMB_W) + STAGES - 1) / STAGES;   // per integrator stage

        // Two's complement wrap of x to w bits, sign-extended back
        local function longint wrap_s(longint x, int w);
            longint m;
            if (w >= 64) return x;
            m = longint'(1) <<< (w - 1);
            x = x & ((longint'(1) <<< w) - 1);
            return (x ^ m) - m;
        endfunction

        // Integrator stage j (0..STAGES-1): input / output widths
        local function int int_win(int j);
            int raw = COMB_W + j * GROWTH;
            if (DECIMATE) return OW;
            if (j == 0)   return COMB_W;
            return (raw > OW) ? OW : raw;
        endfunction

        local function int int_wout(int j);
            int raw = COMB_W + (j + 1) * GROWTH;
            if (DECIMATE)        return OW;
            if (j == STAGES - 1) return OW;
            return (raw > OW) ? OW : raw;
        endfunction

        // Comb stage s (1..STAGES): input / output widths
        local function int comb_win(int s);
            return DECIMATE ? OW : IN_W + s - 1;
        endfunction

        local function int comb_wout(int s);
            return DECIMATE ? OW : IN_W + s;
        endfunction

        virtual function void predict();
            longint xin [int];                         // input sample by clock cycle
            int     last_in = -1, last_out = -1, last_cyc;
            bit     valid_c;
            longint x_c;

            // registers
            longint cs  [1:STAGES][0:DIFF_DELAY];      // comb delay lines
            longint cd  [1:STAGES];                    // comb outputs (registered)
            longint iin [0:STAGES-1];                  // integrator input registers
            longint iq  [0:STAGES-1];                  // integrator accumulators
            longint idout [0:STAGES-1];                // integrator outputs (combinational)
            longint ups = 0, gated = 0, dec = 0, outv = 0;
            int     cnt = 0;
            bit     dv = 0, vreg = DECIMATE ? 0 : 1;   // dec_valid, m_axis.valid

            // next state
            longint ncs [1:STAGES][0:DIFF_DELAY];
            longint ncd [1:STAGES];
            longint niin [0:STAGES-1];
            longint niq  [0:STAGES-1];
            longint nups, ngated, ndec, noutv, d;
            int     ncnt;
            bit     ndv, nvreg;

            for (int i = 0; i < n_in(); i++) begin
                xin[in_cycle(i)] = in_re(i);
                if (in_cycle(i) > last_in) last_in = in_cycle(i);
            end
            if (n_out_obs() > 0) last_out = out_cycle(n_out_obs() - 1);

            // decimator: all outputs appear shortly after the last input
            last_cyc = DECIMATE ? last_in + 4 : last_out;

            for (int s = 1; s <= STAGES; s++) begin
                cd[s] = 0;
                for (int i = 0; i <= DIFF_DELAY; i++) cs[s][i] = 0;
            end
            for (int j = 0; j < STAGES; j++) begin
                iin[j] = 0;
                iq[j]  = 0;
            end

            for (int c = 0; c <= last_cyc; c++) begin
                valid_c = xin.exists(c);
                x_c     = valid_c ? xin[c] : 0;

                // what the output monitor sees in this cycle: registers before the clock edge
                if (vreg) put(outv);

                // integrator outputs: data_out = in_reg + out_q (combinational)
                for (int j = 0; j < STAGES; j++)
                    idout[j] = wrap_s(iin[j] + iq[j], int_wout(j));

                // defaults: hold
                nups = ups; ngated = gated; ndec = dec; ncnt = cnt; ndv = 0;
                for (int s = 1; s <= STAGES; s++) begin
                    ncd[s] = cd[s];
                    for (int i = 0; i <= DIFF_DELAY; i++) ncs[s][i] = cs[s][i];
                end

                // integrators run on every clock
                for (int j = 0; j < STAGES; j++) begin
                    niq[j]  = idout[j];
                    niin[j] = wrap_s((j == 0) ? (DECIMATE ? gated : ups) : idout[j-1], int_win(j));
                end

                if (!DECIMATE) begin
                    // zero stuffing: comb output for one clock after every valid
                    nups  = valid_c ? cd[STAGES] : 0;
                    noutv = idout[STAGES-1] >>> SHIFT;
                    nvreg = 1;
                end else begin
                    ngated = valid_c ? x_c : 0;
                    if (valid_c) begin
                        if (cnt == UPSAMPLING - 1) begin
                            ncnt = 0;
                            ndv  = 1;
                            ndec = idout[STAGES-1];
                        end else begin
                            ncnt = cnt + 1;
                        end
                    end
                    noutv = cd[STAGES] >>> SHIFT;
                    nvreg = dv;
                end

                // comb stages update on valid (interpolator) / dec_valid (decimator)
                if (DECIMATE ? dv : valid_c) begin
                    for (int s = 1; s <= STAGES; s++) begin
                        if (s == 1) d = DECIMATE ? dec : x_c;
                        else        d = cd[s-1];
                        d = wrap_s(d, comb_win(s));
                        ncd[s] = wrap_s(cs[s][0] - cs[s][DIFF_DELAY], comb_wout(s));
                        for (int i = DIFF_DELAY; i > 0; i--) ncs[s][i] = cs[s][i-1];
                        ncs[s][0] = d;
                    end
                end

                // commit
                cs = ncs; cd = ncd; iin = niin; iq = niq;
                ups = nups; gated = ngated; dec = ndec; cnt = ncnt;
                dv = ndv; vreg = nvreg; outv = noutv;
            end
        endfunction

    endclass

endpackage
