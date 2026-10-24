module lock_detector #(
    parameter int UNLOCK_THOLD = 32,
    parameter int UNLOCK_CNT = 32,
    parameter int LOCK_THOLD  = 16,
    parameter int LOCK_CNT   = 8           
)(
    input  logic    clk,
    input  logic    rst,
    axis_if.slave   s_axis_error,

    output logic    locked           // 1 - петля стабильно захвачена, 0 - поиск
);
    // Input processing
    localparam DATA_W = s_axis_error.DATA_WIDTH;
    logic [DATA_W-1:0] abs_err;
    assign abs_err = (s_axis_error.data[DATA_W-1]) ? unsigned'(-s_axis_error.data) : unsigned'(s_axis_error.data);

    localparam int CNT_W = $clog2((LOCK_CNT > UNLOCK_CNT ? LOCK_CNT : UNLOCK_CNT) + 1);
    logic [CNT_W-1:0] cnt; 

    always_ff @(posedge clk) begin
        if (rst) begin
            locked <= 1'b0;
            cnt    <= '0;
        end else if (s_axis_error.valid) begin
            if (!locked) begin
                // Waiting for a stable low error
                if (abs_err < DATA_W'(LOCK_THOLD)) begin
                    if (cnt == CNT_W'(LOCK_CNT-1)) begin
                        locked <= 1'b1;
                        cnt    <= '0;
                    end else
                        cnt <= cnt + 1'b1;
                end else
                    cnt <= '0;
            end else begin
                // Locked: waiting for an error
                if (abs_err > DATA_W'(UNLOCK_THOLD)) begin
                    if (cnt == CNT_W'(UNLOCK_CNT-1)) begin
                        locked <= 1'b0;
                        cnt    <= '0;
                    end else
                        cnt <= cnt + 1'b1;
                end else
                    cnt <= '0;
            end
        end
    end

endmodule