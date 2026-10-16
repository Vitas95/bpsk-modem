`timescale 1ps/1ps
module gardner_error_tb ();

import tb_pkg::*;

// Simulation parameters
parameter   CLK_PERIOD = 10;

localparam  DATA_WIDTH  = 16;  // width of one component (Re or Im)
localparam  FRACT_WIDTH = 14;

// How the DUT output port is derived from the post_adder accumulator.
// Currently in the RTL: m_axis_error.data <= post_adder, i.e. the lowest
// DATA_WIDTH bits are taken without any shift. If scaling is added to the
// module (e.g. >>> FRACT_WIDTH), change OUT_SHIFT here accordingly.
localparam  OUT_SHIFT   = 0;

axis_if #(.DATA_WIDTH(DATA_WIDTH), .FRACT_WIDTH(FRACT_WIDTH), .COMPLEX(1)) data_in();
axis_if #(.DATA_WIDTH(DATA_WIDTH), .FRACT_WIDTH(FRACT_WIDTH)) error_out();

pulse_driver #(DATA_WIDTH, FRACT_WIDTH, 1) drv_a = new(data_in);

bit clk, rst;
always #(CLK_PERIOD/2) clk = ~clk;

gardner_error dut (
    .clk(clk),
    .rst(rst),

    .s_axis(data_in),
    .m_axis_error(error_out)
);

// ---------------------------------------------------------------------------
// Reference model
// ---------------------------------------------------------------------------
// Complex sample in the same format as on the bus: {Im, Re}.
typedef struct packed {
    logic signed [DATA_WIDTH-1:0] im;
    logic signed [DATA_WIDTH-1:0] re;
} cplx_t;

// Gardner error:
//   e = Re{ (x[n] - x[n-2]) * conj(x[n-1]) }
//     = (Re0 - Re2) * Re1  +  (Im0 - Im2) * Im1
// x0 is the newest sample x[n], x1 = x[n-1], x2 = x[n-2].
// The result is returned at full precision (what the 48-bit post_adder in
// the DUT is supposed to accumulate). longint (64 bits) is more than enough.
function automatic longint gardner_error_ref (input cplx_t x0, x1, x2);
    longint d_re, d_im;
    d_re = $signed(x0.re) - $signed(x2.re);
    d_im = $signed(x0.im) - $signed(x2.im);
    return d_re * $signed(x1.re) + d_im * $signed(x1.im);
endfunction

// ---------------------------------------------------------------------------
// Monitors + scoreboard
// ---------------------------------------------------------------------------
cplx_t in_q [$];          // all input samples in order of arrival
int    n_out      = 0;    // number of output samples received
int    n_checked  = 0;    // how many of them were compared with the model
int    n_err      = 0;    // number of mismatches
int    n_overflow = 0;    // expected values that do not fit into the DUT output

// Input monitor. Data is sampled on the same clock edges where the driver
// asserts valid (the driver uses non-blocking assignments, so there is no race).
always @(posedge clk) begin : InputMonitor
    if (!rst && data_in.valid) begin
        cplx_t s;
        s.re = data_in.data[DATA_WIDTH-1:0];
        s.im = data_in.data[2*DATA_WIDTH-1:DATA_WIDTH];
        in_q.push_back(s);
    end
end

// Output monitor. The DUT computes the error on every second input sample,
// starting with the first one (samples with indices 0, 2, 4, ... in 0-based
// numbering). Therefore the m-th output (0-based) corresponds to x[n] = in_q[2*m],
// x[n-1] = in_q[2*m-1], x[n-2] = in_q[2*m-2].
// The very first output (m = 0) is computed from an incomplete history (after
// reset the shift register does not hold three samples yet), so it is not checked.
always @(posedge clk) begin : OutputChecker
    if (!rst && error_out.valid) begin
        int                           m;
        longint                       exp_full, exp_shifted;
        logic signed [DATA_WIDTH-1:0] exp_out;

        m = n_out;
        n_out++;

        if (m == 0) begin
            $display("[%0t] OUT #0: skipped (history is not filled yet), DUT=%0d",
                     $time, $signed(error_out.data));
        end else if (2*m >= in_q.size()) begin
            n_err++;
            $display("[%0t] ERROR: OUT #%0d has no matching input samples (got %0d inputs)",
                     $time, m, in_q.size());
        end else begin
            exp_full    = gardner_error_ref(in_q[2*m], in_q[2*m-1], in_q[2*m-2]);
            exp_shifted = exp_full >>> OUT_SHIFT;
            exp_out     = exp_shifted[DATA_WIDTH-1:0];

            n_checked++;
            if (exp_shifted != longint'(exp_out)) n_overflow++;

            // !== so that X/Z on the DUT output are also counted as errors
            if (error_out.data !== exp_out) begin
                n_err++;
                $display("[%0t] ERROR: OUT #%0d: DUT=%0d (0x%h), expected=%0d (0x%h), full-precision=%0d",
                         $time, m, $signed(error_out.data), error_out.data,
                         exp_out, exp_out, exp_full);
            end else begin
                $display("[%0t] OK:    OUT #%0d: %0d", $time, m, exp_out);
            end
        end
    end
end

// ---------------------------------------------------------------------------
// Stimulus + final report
// ---------------------------------------------------------------------------
int exp_n_out;

initial begin
clk <= 0;
rst <= 1;
data_in.valid <= 0;
data_in.data <= 0;
#(3*CLK_PERIOD);
rst <= 0;
@(posedge clk);
drv_a.apply_pulse_from_file (clk, "../test_data.txt", 40, 0);

// Let the DUT pipeline finish processing the last sample
repeat (100) @(posedge clk);

// The DUT produces one result per odd-numbered input sample (1st, 3rd, ...)
exp_n_out = (in_q.size() + 1) / 2;
if (n_out != exp_n_out) begin
    n_err++;
    $display("ERROR: number of outputs = %0d, expected %0d (inputs: %0d)",
             n_out, exp_n_out, in_q.size());
end

if (n_checked == 0) begin
    n_err++;
    $display("ERROR: nothing was checked (is ../test_data.txt missing or too short?)");
end

if (n_overflow != 0)
    $display("WARNING: %0d of %0d expected values do not fit into %0d output bits (OUT_SHIFT=%0d); DUT output is truncated",
             n_overflow, n_checked, DATA_WIDTH, OUT_SHIFT);

$display("----------------------------------------------------------------");
if (n_err == 0)
    $display("TEST PASSED: %0d outputs checked, 0 errors", n_checked);
else
    $display("TEST FAILED: %0d errors, %0d outputs checked", n_err, n_checked);
$display("----------------------------------------------------------------");
$stop;
end

endmodule