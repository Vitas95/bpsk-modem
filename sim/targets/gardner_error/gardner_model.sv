// Reference model of gardner_error (module specific, used by gardner_error_tb).
package gardner_model;

    // W         - width of one input component (Re or Im)
    // OUT_SHIFT - how the DUT output is derived from the post_adder accumulator.
    //             Now: m_axis_error.data <= post_adder (low bits, no shift).
    //             If scaling is added to the RTL (e.g. >>> FRACT_WIDTH), change it here.
    class gardner_model #(int W = 16, int OUT_SHIFT = 0)
        extends tb_pkg::axis_model #(W, 1, W, 0);

        // Gardner error: e = Re{ (x[n] - x[n-2]) * conj(x[n-1]) }
        //                  = (Re0 - Re2) * Re1 + (Im0 - Im2) * Im1
        // x0 is the newest sample, full precision (the 48-bit post_adder in the DUT).
        local function longint error_ref(int n0, int n1, int n2);
            longint d_re = in_re(n0) - in_re(n2);
            longint d_im = in_im(n0) - in_im(n2);
            return d_re * in_re(n1) + d_im * in_im(n1);
        endfunction

        // The DUT computes the error on every second input sample, starting with the
        // first one (0, 2, 4, ...): output m uses in[2m], in[2m-1], in[2m-2].
        // Output 0 is computed from an incomplete history after reset: not checked.
        virtual function void predict();
            for (int m = 0; m < (n_in() + 1) / 2; m++) begin
                if (m == 0) put_dc();
                else        put(error_ref(2*m, 2*m-1, 2*m-2) >>> OUT_SHIFT);
            end
        endfunction

    endclass

endpackage