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

    // // Symmetric FIR coefficients without cic compensation
    // (* rom_style = "distributed" *) logic signed [COEFF_WIDTH-1:0] mem [0:(COEFF_NUM+1)/2-1] = '{
    // -4, 0, 17, 38, 57, 64
    // };

    // Symmetric FIR coefficients with cic compensation
    // (* rom_style = "distributed" *) logic signed [COEFF_WIDTH-1:0] mem [0:(COEFF_NUM+1)/2-1] = '{
    // 2, -12, -4, 26, 78, 128, 150
    // };
    (* rom_style = "distributed" *) logic signed [COEFF_WIDTH-1:0] mem [0:(COEFF_NUM+1)/2-1] = '{
        1, -6, -2, 13, 39, 64, 75
    };


    always_ff @(posedge clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
        rd_data <= mem[rd_addr];
    end

endmodule