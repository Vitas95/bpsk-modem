// Reference model of pi_controller (module specific, used by pi_controller_tb).
package pi_controller_model;

    function automatic shortreal calculate_pi (
        input logic [15:0] error,
        input shortreal Kp,          // proportional coefficient
        input shortreal Ki,          // Integral coefficient
        input shortreal i_state_in,  // Old integrator value
        output shortreal i_state_out // New integrator value
    );
        shortreal p_term;
        shortreal i_term;
        shortreal raw_output;
        shortreal final_output;

        // Proportional
        p_term = Kp * $itor(signed'(error));

        // Integral
        i_term = i_state_in + Ki * $itor(signed'(error));
        i_state_out = i_term;

        raw_output = p_term + i_term;

        final_output = $floor(raw_output/2**15);

        return final_output;
    endfunction

    // One output per input sample, in the same order.
    class pi_model extends tb_pkg::axis_model #(16, 0, 16, 0);

        shortreal kp = $floor(0.005  * 2**15);
        shortreal ki = $floor(0.0005 * 2**15);

        virtual function void predict();
            shortreal i_state = 0;   // integrator is cleared by reset
            shortreal y;
            for (int i = 0; i < n_in(); i++) begin
                y = calculate_pi(in_raw(i), kp, ki, i_state, i_state);
                put(longint'(y));
            end
        endfunction

    endclass

endpackage