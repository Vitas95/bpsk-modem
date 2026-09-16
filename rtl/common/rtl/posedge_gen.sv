module posedge_gen(
    input  logic clk,
    input  logic in,
    output logic out
);

logic delay;
always_ff @(posedge clk) delay <= in;
assign out = in & !delay;
    
endmodule