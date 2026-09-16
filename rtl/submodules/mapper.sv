`include "axis_checks.svh"
//////////////////////////////////////////////////////////////////////////////////
// Module: mapper
// Description:
//   Convert input bitstream into the sample stream and form the sample rate.
//   There are no ready in axistream buses after this block in the transmitter.
//////////////////////////////////////////////////////////////////////////////////

module mapper #(
    parameter CLK_PER_SAMPLE
)(
    input clk,
    input rst,

    axis_if.slave  data_in,
    axis_if.master data_out
);

`CHECK_AXIS_WIDTH(data_in, 1)
`CHECK_AXIS_WIDTH(data_out, 2)

localparam int CNT_WIDTH = (CLK_PER_SAMPLE > 1) ? $clog2(CLK_PER_SAMPLE) : 1;
logic [CNT_WIDTH-1:0]   samplerate_cnt;
logic                   advance;
logic                   state;
logic                   samplerate_cnt_rst;

assign advance = data_in.valid && data_in.ready;
assign samplerate_cnt_rst = (samplerate_cnt == (CLK_PER_SAMPLE - 2));

always_ff @( posedge clk ) begin
    if      (rst)   samplerate_cnt <= 0;
    else if (state) samplerate_cnt <= samplerate_cnt + 1;
    else            samplerate_cnt <= 0;
end

always_ff @( posedge clk ) begin
    if (rst) begin
        samplerate_cnt <= '0;
        data_in.ready  <=  1;
        data_out.valid <=  0;
        data_out.data  <= '0;
        state          <=  0; 
    end else begin
        if (advance ) begin
            state          <= 1;
            data_in.ready  <= 0;
            data_out.valid <= 1;
            case(data_in.data)
		        1'b0: 	 data_out.data <= 2'b11;
		        1'b1: 	 data_out.data <= 2'b01;
		        default: data_out.data <= 2'b00; 
	        endcase
        end else if (samplerate_cnt_rst)  begin
            state          <= 0;
            data_in.ready  <= 1;
        end else begin
            data_out.valid <= 0;
        end
    end
end



endmodule