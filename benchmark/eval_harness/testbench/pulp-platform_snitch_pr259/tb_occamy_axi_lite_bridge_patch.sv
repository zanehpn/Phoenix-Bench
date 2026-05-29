`timescale 1ns/1ps

module tb_occamy_axi_lite_bridge_patch;

  localparam string SNAP_ROOT = "../../snapshots/pulp-platform_snitch_pr259";
  localparam string OCCAMY_TOP = {SNAP_ROOT, "/hw/system/occamy/src/occamy_top.sv"};
  localparam string OCCAMY_PKG = {SNAP_ROOT, "/hw/system/occamy/src/occamy_pkg.sv"};

  function automatic bit file_contains(string path, string needle);
    int fd;
    string line;
    string lowered;

    fd = $fopen(path, "r");
    if (fd == 0) begin
      $display("FAIL: Unable to open %s", path);
      file_contains = 1'b0;
      return file_contains;
    end

    file_contains = 1'b0;
    while (!$feof(fd)) begin
      void'($fgets(line, fd));
      // Manual substring scan (string.find not universally supported).
      begin
        string hay = line;
        string nd  = needle;
        int h_len = hay.len();
        int n_len = nd.len();
        if (n_len > 0 && n_len <= h_len) begin
          for (int i = 0; i <= h_len - n_len; i++) begin
            bit match = 1'b1;
            for (int j = 0; j < n_len; j++) begin
              if (hay[i + j] != nd[j]) begin match = 1'b0; break; end
            end
            if (match) begin file_contains = 1'b1; break; end
          end
          if (file_contains) break;
        end
      end
    end

    $fclose(fd);
  endfunction

  // ---- Patch-related functional coverage ----
  // PR259: AXI-Lite crossbar gets SOC output port and connects back to narrow AXI
  bit cov_pkg_soc_output;
  bit cov_pkg_periph_input;
  bit cov_top_to_soc_cdc;
  bit cov_top_to_axi_bridge;

  covergroup cg_inst;
    cp_pkg_soc_output: coverpoint cov_pkg_soc_output {
      bins present = {1'b1};
    }
    cp_pkg_periph_input: coverpoint cov_pkg_periph_input {
      bins present = {1'b1};
    }
    cp_top_to_soc_cdc: coverpoint cov_top_to_soc_cdc {
      bins present = {1'b1};
    }
    cp_top_to_axi_bridge: coverpoint cov_top_to_axi_bridge {
      bins present = {1'b1};
    }
  endgroup

  cg_inst cg = new();

  // Declarations hoisted to module scope (Verilator 5.020 rejects nested
  // variable decls inside initial after executable statements).
  bit pkg_has_soc_output;
  bit pkg_has_periph_input;
  bit top_has_to_soc_cdc;
  bit top_has_to_axi_bridge;

  initial begin
    begin
      int _fd_top, _fd_pkg;
      _fd_top = $fopen(OCCAMY_TOP, "r");
      _fd_pkg = $fopen(OCCAMY_PKG, "r");
      if (_fd_top) $fclose(_fd_top);
      if (_fd_pkg) $fclose(_fd_pkg);
      if (_fd_top == 0 || _fd_pkg == 0) begin
        $fatal(1, "FAIL: Missing Occamy sources in snapshot.");
      end
    end

    pkg_has_soc_output = file_contains(OCCAMY_PKG, "SOC_AXI_LITE_PERIPH_XBAR_OUT_SOC");
    pkg_has_periph_input = file_contains(OCCAMY_PKG, "SOC_NARROW_XBAR_IN_PERIPH");
    top_has_to_soc_cdc = file_contains(OCCAMY_TOP, "i_axi_lite_to_soc_cdc");
    top_has_to_axi_bridge = file_contains(OCCAMY_TOP, "i_axi_lite_to_axi_periph_pc");

    cov_pkg_soc_output   = pkg_has_soc_output;
    cov_pkg_periph_input = pkg_has_periph_input;
    cov_top_to_soc_cdc   = top_has_to_soc_cdc;
    cov_top_to_axi_bridge = top_has_to_axi_bridge;
    cg.sample();

    if (pkg_has_soc_output && pkg_has_periph_input &&
        top_has_to_soc_cdc && top_has_to_axi_bridge) begin
      $display("PASS: Occamy AXI-Lite crossbar exposes SOC output and connects back into the narrow AXI fabric.");
      $display("Functional Coverage: cg_inst = %0.2f%%", cg.get_inst_coverage());
      $finish;
    end else begin
      $display("FAIL: Occamy AXI-Lite SBA bridge is incomplete (missing enumerations or connectivity).");
      $finish(1);
    end
  end


  initial begin
    $dumpfile("tb_occamy_axi_lite_bridge_patch.vcd");
    $dumpvars(0);
  end

endmodule
