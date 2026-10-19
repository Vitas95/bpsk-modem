// =============================================================================
// tb_pkg: common building blocks for module testbenches.
//
// A testbench for a stream (AXI-Stream like) module is:
//
//     `timescale 1ps/1ps
//     module my_tb;
//         import tb_pkg::*;
//         import my_model_pkg::*;                // targets/my/my_model.sv (optional)
//
//         tb_clk_if sys();                       // clock + reset
//         axis_if #(16,14,0) data_in();
//         axis_if #(16,14,0) data_out();
//
//         my_module dut (.clk(sys.clk), .rst(sys.rst), .s_axis(data_in), .m_axis(data_out));
//
//         my_model model = new();                // or: axis_model #(16,0,16,0) model = null;
//         axis_env #(16,14,0, 16,14,0) env = new(sys, data_in, data_out, model);
//
//         initial env.run("../test_data.txt", 40);
//     endmodule
//
// env.run(): reset -> stimulus from file -> wait until the DUT output goes quiet
// -> run the model -> compare -> print ONE result line -> $stop.
// Nothing is printed for matching samples; only the first mismatch is printed.
//
// Custom scenarios (extra control ports, several phases) use the same pieces:
//     env.reset();  ...  env.drv.apply_file("../x.txt", 20);  ...  env.finish();
//
// Assumptions about axis_if: parameters DATA_WIDTH, FRACT_WIDTH, COMPLEX,
// HAS_READY; signals valid, data, ready; complex data is {Im, Re}.
// Interfaces without a model are only observed (result line says NOT CHECKED).
// =============================================================================
package tb_pkg;

    timeunit 1ps;
    timeprecision 1ps;

    // -------------------------------------------------------------------------
    // Error counter and the final PASSED / FAILED line.
    // Only the first max_shown failed checks are printed; the rest are counted.
    // -------------------------------------------------------------------------
    class test_report;

        int n_checked     = 0;   // comparisons performed
        int n_fail        = 0;   // failed comparisons
        int n_err         = 0;   // structural errors (wrong item count, missing file, ...)
        int n_warn        = 0;
        int n_shown       = 0;   // failed comparisons already printed
        int max_shown     = 1;
        bit verbose       = 0;   // 1 = also print every passed check
        bit observe_only  = 0;   // no reference model: nothing to check, not a failure

        function void ok(string msg = "");
            n_checked++;
            if (verbose && msg != "") $display("OK:    %s", msg);
        endfunction

        function void fail(string msg);
            n_checked++;
            n_fail++;
            if (n_shown < max_shown) begin
                n_shown++;
                $display("ERROR: %s", msg);
            end
        endfunction

        // Convenience for custom checks. Note: msg is evaluated even when pass = 1.
        function void check(bit pass, string msg);
            if (pass) ok(msg); else fail(msg);
        endfunction

        // Structural error, always printed
        function void error(string msg);
            n_err++;
            $display("ERROR: %s", msg);
        endfunction

        function void warning(string msg);
            n_warn++;
            $display("WARNING: %s", msg);
        endfunction

        function void summary();
            $display("--------------------------------");
            if (n_err != 0 || n_fail != 0)
                $display("TEST FAILED: %0d of %0d checks failed, %0d other errors", n_fail, n_checked, n_err);
            else if (observe_only)
                $display("TEST NOT CHECKED: no reference model, outputs were only observed");
            else if (n_checked == 0)
                $display("TEST FAILED: nothing was checked");
            else
                $display("TEST PASSED: %0d checks%s", n_checked,
                         (n_warn != 0) ? $sformatf(", %0d warnings", n_warn) : "");
            $display("--------------------------------");
        endfunction

    endclass

    // -------------------------------------------------------------------------
    // Passive monitor: records every transfer (valid, and ready if HAS_READY).
    // Complex data layout is {Im, Re}.
    // -------------------------------------------------------------------------
    class axis_monitor #(int DATA_WIDTH = 16, int FRACT_WIDTH = 14, int COMPLEX = 0, int HAS_READY = 0);

        localparam int WORD_WIDTH = DATA_WIDTH * (1 + COMPLEX);

        virtual axis_if #(.DATA_WIDTH(DATA_WIDTH), .FRACT_WIDTH(FRACT_WIDTH),
                          .COMPLEX(COMPLEX), .HAS_READY(HAS_READY)) vif;

        logic [WORD_WIDTH-1:0] data_q [$];
        time                   time_q [$];   // simulation time of every transfer (to find it in the waves)
        int                    cyc_q  [$];   // clock cycle of every transfer; cycle 0 = first sample() call
        int                    cycle = 0;

        function new(virtual axis_if #(.DATA_WIDTH(DATA_WIDTH), .FRACT_WIDTH(FRACT_WIDTH),
                                       .COMPLEX(COMPLEX), .HAS_READY(HAS_READY)) vif);
            this.vif = vif;
        endfunction

        // Call on every rising clock edge. valid is compared with === so X/Z is never a transfer.
        function void sample(bit enable = 1);
            if (enable && vif.valid === 1'b1 && (HAS_READY == 0 || vif.ready === 1'b1)) begin
                data_q.push_back(vif.data);
                time_q.push_back($time);
                cyc_q.push_back(cycle);
            end
            cycle++;
        endfunction

        function int size();
            return data_q.size();
        endfunction

        function void clear();
            data_q.delete();
            time_q.delete();
            cyc_q.delete();
        endfunction

        function logic [WORD_WIDTH-1:0] raw(int idx);
            return data_q[idx];
        endfunction

    endclass

    // -------------------------------------------------------------------------
    // Stimulus driver. File format: one sample per line ("%d"); for complex
    // data either "re im" or a single value used for both parts.
    // -------------------------------------------------------------------------
    class pulse_driver #(int DATA_WIDTH = 16, int FRACT_WIDTH = 14, int COMPLEX = 0, int HAS_READY = 0);

        localparam int WORD_WIDTH = DATA_WIDTH * (1 + COMPLEX);

        virtual tb_clk_if sys;
        virtual axis_if #(.DATA_WIDTH(DATA_WIDTH), .FRACT_WIDTH(FRACT_WIDTH),
                          .COMPLEX(COMPLEX), .HAS_READY(HAS_READY)) vif;

        test_report rpt;                       // set by axis_env
        int         n_sent        = 0;
        int         ready_timeout = 100000;    // clocks to wait for ready before giving up
        bit         aborted       = 0;

        function new(virtual tb_clk_if sys,
                     virtual axis_if #(.DATA_WIDTH(DATA_WIDTH), .FRACT_WIDTH(FRACT_WIDTH),
                                       .COMPLEX(COMPLEX), .HAS_READY(HAS_READY)) vif);
            this.sys = sys;
            this.vif = vif;
        endfunction

        function void err(string msg);
            if (rpt != null) rpt.error(msg); else $display("ERROR: %s", msg);
        endfunction

        task idle();
            vif.valid <= 0;
            vif.data  <= 0;
        endtask

        // One transfer, then clk_per_valid-1 idle clocks
        task send(input logic [WORD_WIDTH-1:0] word, input int clk_per_valid);
            int waited = 0;
            vif.valid <= 1;
            vif.data  <= word;
            do begin
                @(posedge sys.clk);
                waited++;
            end while (HAS_READY != 0 && vif.ready !== 1'b1 && waited < ready_timeout);
            vif.valid <= 0;
            if (HAS_READY != 0 && vif.ready !== 1'b1) begin
                err($sformatf("driver: ready did not come within %0d clocks", ready_timeout));
                aborted = 1;
                return;
            end
            n_sent++;
            if (clk_per_valid > 1) repeat (clk_per_valid - 1) @(posedge sys.clk);
        endtask

        // delay = number of zero samples sent before the file data
        task apply_file(input string filename, input int clk_per_valid = 20, input int delay = 0);
            int    fd, n, a, b;
            string line;
            logic [DATA_WIDTH-1:0] re, im;

            fd = $fopen(filename, "r");
            if (fd == 0) begin
                err($sformatf("cannot open stimulus file: %s", filename));
                return;
            end

            idle();
            @(posedge sys.clk);

            repeat (delay) if (!aborted) send('0, clk_per_valid);

            while (!aborted && $fgets(line, fd)) begin
                n = $sscanf(line, "%d %d", a, b);
                if (n < 2) begin                    // single column (or not a number)
                    n = $sscanf(line, "%d", a);
                    b = a;
                end
                if (n >= 1) begin
                    re = a;
                    im = b;
                    send(COMPLEX ? WORD_WIDTH'({im, re}) : WORD_WIDTH'(re), clk_per_valid);
                end
            end

            $fclose(fd);
            idle();
        endtask

        // n random words (up to 64 bits wide)
        task apply_random(input int n, input int clk_per_valid = 20);
            idle();
            @(posedge sys.clk);
            repeat (n) if (!aborted) send(WORD_WIDTH'({$urandom(), $urandom()}), clk_per_valid);
            idle();
        endtask

    endclass

    // -------------------------------------------------------------------------
    // Base class of a reference model, the only thing that is module specific.
    // Derive a class (put it in the module's folder), implement predict():
    // read the applied input with n_in()/in_re()/in_im()/in_raw() and push the
    // expected output words, in order, with put()/put_raw()/put_dc().
    // -------------------------------------------------------------------------
    virtual class axis_model #(int IN_W = 16, int IN_CPLX = 0, int OUT_W = 16, int OUT_CPLX = 0);

        localparam int IN_WORD  = IN_W  * (1 + IN_CPLX);
        localparam int OUT_WORD = OUT_W * (1 + OUT_CPLX);

        typedef logic [IN_WORD-1:0]  in_word_t;
        typedef logic [OUT_WORD-1:0] out_word_t;

        in_word_t    in_q   [$];   // filled by axis_env before predict()
        int          in_cyc_q  [$];  // clock cycle of every input transfer (see in_cycle)
        int          out_cyc_q [$];  // clock cycle of every output transfer the DUT produced
        out_word_t   exp_q  [$];
        bit          dc_q   [$];   // 1 = this output is not checked
        int          n_trunc = 0;  // expected values that do not fit into the output width
        test_report  rpt;

        pure virtual function void predict();

        // ---- input access ----
        function int n_in();
            return in_q.size();
        endfunction

        // Clock cycles are counted from the first clock edge after env.reset() returns (cycle 0).
        // For models that must follow the DUT clock by clock (free-running outputs,
        // zero stuffing): when input i was applied, and when/how many outputs were seen.
        function int in_cycle(int i);
            return in_cyc_q[i];
        endfunction

        function int n_out_obs();
            return out_cyc_q.size();
        endfunction

        function int out_cycle(int j);
            return out_cyc_q[j];
        endfunction

        function logic [IN_WORD-1:0] in_raw(int i);
            return in_q[i];
        endfunction

        // Real part (or the whole sample) sign-extended. For 1-bit data use in_raw().
        function longint in_re(int i);
            logic [IN_WORD-1:0] w = in_q[i];
            logic signed [IN_W-1:0] r = w[IN_W-1:0];
            return longint'(r);
        endfunction

        // Imaginary part sign-extended (0 for real data)
        function longint in_im(int i);
            logic [IN_WORD-1:0] w = in_q[i];
            logic signed [IN_W-1:0] r;
            if (IN_CPLX == 0) return 0;
            r = w[IN_WORD-1 -: IN_W];
            return longint'(r);
        endfunction

        // ---- expected output ----
        // Values are truncated to the output width like the hardware does;
        // a value that does not fit (neither signed nor unsigned) is counted in n_trunc.
        function void put(longint re, longint im = 0);
            logic [OUT_W-1:0] r = re[OUT_W-1:0];
            logic [OUT_W-1:0] i = im[OUT_W-1:0];
            if (!fits(re) || (OUT_CPLX != 0 && !fits(im))) n_trunc++;
            exp_q.push_back(OUT_CPLX ? OUT_WORD'({i, r}) : OUT_WORD'(r));
            dc_q.push_back(0);
        endfunction

        function void put_raw(out_word_t w);
            exp_q.push_back(w);
            dc_q.push_back(0);
        endfunction

        // Output that exists but must not be compared (e.g. history not filled after reset)
        function void put_dc();
            exp_q.push_back('0);
            dc_q.push_back(1);
        endfunction

        function bit fits(longint v);
            if (OUT_W >= 63) return 1;
            return (v >= -(longint'(1) <<< (OUT_W-1))) && (v < (longint'(1) <<< OUT_W));
        endfunction

    endclass

    // -------------------------------------------------------------------------
    // Test environment for one input stream and one output stream.
    // -------------------------------------------------------------------------
    class axis_env #(int IN_W  = 16, int IN_FR  = 14, int IN_CPLX  = 0,
                     int OUT_W = 16, int OUT_FR = 14, int OUT_CPLX = 0,
                     int IN_RDY = 0, int OUT_RDY = 0);

        typedef axis_model #(IN_W, IN_CPLX, OUT_W, OUT_CPLX) model_t;
        localparam int OUT_WORD = OUT_W * (1 + OUT_CPLX);

        virtual tb_clk_if sys;
        pulse_driver #(IN_W,  IN_FR,  IN_CPLX,  IN_RDY)  drv;
        axis_monitor #(IN_W,  IN_FR,  IN_CPLX,  IN_RDY)  in_mon;
        axis_monitor #(OUT_W, OUT_FR, OUT_CPLX, OUT_RDY) out_mon;
        test_report rpt;
        model_t     model;                 // null = observe only

        bit stop_at_end = 1;               // $stop (or $finish with +tb_finish) at the end of finish()
        int max_drain   = 100000;          // upper limit of the wait for the DUT to go quiet, clocks
        int fixed_drain = 0;               // >0: wait exactly this many clocks after the stimulus
                                           // (for outputs that never go quiet, e.g. valid always 1)
        bit sampling    = 0;

        function new(virtual tb_clk_if sys,
                     virtual axis_if #(.DATA_WIDTH(IN_W), .FRACT_WIDTH(IN_FR), .COMPLEX(IN_CPLX), .HAS_READY(IN_RDY)) in_if,
                     virtual axis_if #(.DATA_WIDTH(OUT_W), .FRACT_WIDTH(OUT_FR), .COMPLEX(OUT_CPLX), .HAS_READY(OUT_RDY)) out_if,
                     model_t model = null);
            this.sys     = sys;
            this.drv     = new(sys, in_if);
            this.in_mon  = new(in_if);
            this.out_mon = new(out_if);
            this.rpt     = new();
            this.model   = model;
            this.drv.rpt = this.rpt;
            if (model != null) model.rpt = this.rpt;
            else               rpt.observe_only = 1;
        endfunction

        // Reset the DUT (driven on the falling edge, no race with the DUT) and start the monitors
        task reset(input int cycles = 3);
            drv.idle();
            sys.rst = 1;
            repeat (cycles) @(posedge sys.clk);
            @(negedge sys.clk);
            sys.rst = 0;
            @(posedge sys.clk);
            if (!sampling) begin
                sampling = 1;
                fork
                    forever begin
                        @(posedge sys.clk);
                        in_mon.sample(!sys.rst);
                        out_mon.sample(!sys.rst);
                    end
                join_none
            end
        endtask

        // Wait until the DUT output has been quiet for quiet_cycles clocks
        // (run() passes max(100, 2*clk_per_valid))
        task drain(input int quiet_cycles);
            int idle_cnt = 0, total = 0, last = out_mon.size();
            while (idle_cnt < quiet_cycles && total < max_drain) begin
                @(posedge sys.clk);
                total++;
                if (out_mon.size() != last) begin
                    last = out_mon.size();
                    idle_cnt = 0;
                end else idle_cnt++;
            end
            if (total >= max_drain) rpt.warning("DUT output did not go quiet, stopped waiting");
        endtask

        function string fmt(logic [OUT_WORD-1:0] w);
            logic [OUT_W-1:0] re = w[OUT_W-1:0];
            logic [OUT_W-1:0] im;
            if (OUT_CPLX != 0) begin
                im = w[OUT_WORD-1 -: OUT_W];
                return $sformatf("re=%0d im=%0d (0x%h)", $signed(re), $signed(im), w);
            end
            return (OUT_W > 1) ? $sformatf("%0d (0x%h)", $signed(re), w) : $sformatf("%b", w);
        endfunction

        // Run the model on the recorded input and compare with the recorded output
        function void check();
            int n_cmp;
            model.in_q.delete();
            model.exp_q.delete();
            model.dc_q.delete();
            model.n_trunc = 0;
            foreach (in_mon.data_q[i]) model.in_q.push_back(in_mon.data_q[i]);
            model.in_cyc_q  = in_mon.cyc_q;
            model.out_cyc_q = out_mon.cyc_q;

            model.predict();

            if (model.exp_q.size() != out_mon.size())
                rpt.error($sformatf("number of outputs = %0d, expected %0d (inputs: %0d)",
                                    out_mon.size(), model.exp_q.size(), in_mon.size()));

            n_cmp = (model.exp_q.size() < out_mon.size()) ? model.exp_q.size() : out_mon.size();

            for (int i = 0; i < n_cmp; i++) begin
                if (model.dc_q[i]) continue;
                // === so that X/Z on the DUT output counts as an error
                if (out_mon.raw(i) === model.exp_q[i]) rpt.ok();
                else rpt.fail($sformatf("OUT #%0d (t=%0t): DUT=%s, expected=%s",
                                        i, out_mon.time_q[i], fmt(out_mon.raw(i)), fmt(model.exp_q[i])));
            end

            if (model.n_trunc != 0)
                rpt.warning($sformatf("%0d of %0d expected values do not fit into the output width, compared truncated",
                                      model.n_trunc, model.exp_q.size()));
        endfunction

        // Wait for the pipeline, check, report, stop
        task finish(input int quiet_cycles = 0);
            if (fixed_drain > 0) repeat (fixed_drain) @(posedge sys.clk);
            else                 drain((quiet_cycles > 0) ? quiet_cycles : 100);
            if (model != null) check();
            else $display("INFO: %0d input and %0d output samples observed", in_mon.size(), out_mon.size());
            rpt.summary();
            if (stop_at_end) begin
                if ($test$plusargs("tb_finish")) $finish;
                else $stop;
            end
        endtask

        // Whole test from a stimulus file
        task run(input string filename, input int clk_per_valid = 20, input int delay = 0);
            reset();
            drv.apply_file(filename, clk_per_valid, delay);
            finish((2 * clk_per_valid > 100) ? 2 * clk_per_valid : 100);
        endtask

        // Whole test with n random input words
        task run_random(input int n, input int clk_per_valid = 20);
            reset();
            drv.apply_random(n, clk_per_valid);
            finish((2 * clk_per_valid > 100) ? 2 * clk_per_valid : 100);
        endtask

    endclass

endpackage
