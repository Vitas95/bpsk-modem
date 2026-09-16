`include "axis_checks.svh"
//////////////////////////////////////////////////////////////////////////////////
// Module: prbs_gen
// Description:
//   Random data generator based on an 8-bit LFSR (Linear Feedback Shift Register).
//   The sequence is pseudo-random and repeats cyclically. The interface is 
//	 AXI4-Stream compatible (with tready and tlast).
//////////////////////////////////////////////////////////////////////////////////
module prbs_gen #(
	parameter SEED
)(
    input	clk,
    input 	rst,

    axis_if.master	gen_out
);

`CHECK_AXIS_WIDTH(gen_out, 1)

logic [7:0] shift_reg;
logic 		advance;
assign 		advance = gen_out.valid && gen_out.ready;

// Main logic
always_ff @(posedge clk) begin
	if (rst) begin 
		shift_reg	  <= SEED;
		gen_out.valid <=  0;
	end else begin 
		gen_out.valid <= 1;
		
		if (advance) begin
			if (shift_reg[0] == 1) 
				shift_reg <= (shift_reg >> 1) ^ 8'b10111000;
			else
				shift_reg <= (shift_reg >> 1);
		end
	end
end

assign gen_out.data = shift_reg[0];

endmodule
