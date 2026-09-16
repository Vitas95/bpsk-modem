package tb_pkg;

    class pulse_driver #(int DATA_WIDTH = 16);

        virtual axis_if #(.DATA_WIDTH(DATA_WIDTH)) vif;

        function new(virtual axis_if #(DATA_WIDTH) vif);
            this.vif = vif;
        endfunction

        task apply_pulse_from_file (
            ref bit clk,
            input string filename,
            input int    clk_per_valid,
            input int    delay
        );
            int    fd;
            string line_str;
            int    sample_val;

            fd = $fopen(filename, "r");
            if (fd == 0) begin
                $display("[apply_pulse_from_file] ERROR: cannot open file: %s", filename);
                return;
            end

            vif.valid <= 0;
            vif.data  <= 0;
            @(posedge clk);

            repeat (delay) begin
                vif.valid <= 1;
                vif.data  <= 0;
                @(posedge clk);

                vif.valid <= 0;
                if (clk_per_valid > 1)
                    repeat (clk_per_valid - 1) @(posedge clk);
            end

            while ($fgets(line_str, fd)) begin
                if ($sscanf(line_str, "%d", sample_val) == 1) begin
                    vif.valid <= 1;
                    vif.data  <= sample_val;
                    @(posedge clk);

                    vif.valid <= 0;
                    if (clk_per_valid > 1)
                        repeat (clk_per_valid - 1) @(posedge clk);
                end
            end

            $fclose(fd);
            vif.valid <= 0;
        endtask

    endclass

endpackage