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