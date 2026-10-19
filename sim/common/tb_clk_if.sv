// Clock + reset generator for testbenches. Instantiate once: tb_clk_if sys();
// and connect the DUT with .clk(sys.clk), .rst(sys.rst).
// The reset sequence is driven by tb_pkg::axis_env (reset/run), not by the testbench.
interface tb_clk_if;
    timeunit 1ps;
    timeprecision 1ps;

    bit  clk    = 0;
    bit  rst    = 1;      // active high, released by axis_env.reset()
    real period = 10.0;   // in ps; change with: initial sys.period = 20;

    initial begin
        #0;               // let the testbench's initial blocks change period first
        forever #(period/2.0) clk = ~clk;
    end
endinterface
