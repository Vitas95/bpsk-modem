module coeff_mem #(
    parameter COEFF_WIDTH,
    parameter COEFF_NUM,
    localparam ADDR_WIDTH  = $clog2((COEFF_NUM+1)/2)
) (
    input  logic                        clk,

    // Write port
    input  logic                        wr_en,
    input  logic [ADDR_WIDTH-1:0]       wr_addr,
    input  logic signed [COEFF_WIDTH-1:0] wr_data,

    // Read port (synchronous, registered output)
    input  logic [ADDR_WIDTH-1:0]       rd_addr,
    output logic signed [COEFF_WIDTH-1:0] rd_data
);

    // Symmetric FIR SRRC coefficients with cic compensation
    (* rom_style = "distributed" *) logic signed [COEFF_WIDTH-1:0] mem [0:9] = '{
    -105, 753, 369, -1050, -2478, -1978, 1758, 7997, 13938, 16384
    };


    always_ff @(posedge clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
        rd_data <= mem[rd_addr];
    end

endmodule