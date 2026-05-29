`timescale 1ns/1ps

module tb_carfield_l2_amo_patch;

  localparam string SNAP_BASE = "../../snapshots/pulp-platform_carfield_pr41";
  localparam string L2_WRAP   = {SNAP_BASE, "/hw/l2_wrap.sv"};
  localparam string CARFIELD  = {SNAP_BASE, "/hw/carfield.sv"};

  function automatic int str_len(input string s);
    int len;
    len = 0;
    foreach (s[i]) len++;
    return len;
  endfunction

  function automatic bit contains(input string haystack, input string needle);
    int h_len;
    int n_len;

    h_len = str_len(haystack);
    n_len = str_len(needle);
    if (n_len == 0) return 1'b1;
    if (n_len > h_len) return 1'b0;

    for (int i = 0; i <= h_len - n_len; i++) begin
      bit match = 1'b1;
      for (int j = 0; j < n_len; j++) begin
        if (haystack[i + j] != needle[j]) begin
          match = 1'b0;
          break;
        end
      end
      if (match) return 1'b1;
    end
    return 1'b0;
  endfunction

  function automatic bit file_contains(string path, string needle);
    int fd;
    string line;
    file_contains = 1'b0;
    fd = $fopen(path, "r");
    if (fd == 0) begin
      $fatal(1, "FAIL: Unable to open %s", path);
    end
    while (!$feof(fd)) begin
      void'($fgets(line, fd));
      if (str_len(line) != 0 && contains(line, needle)) begin
        file_contains = 1'b1;
        break;
      end
    end
    $fclose(fd);
  endfunction

  // -------------------------------------------------------------------------
  // Patch-related functional coverage
  // -------------------------------------------------------------------------
  // PR41 adds atomics support to shared L2 memory.  We cover that each AMO
  // parameter is present in both l2_wrap.sv and carfield.sv.
  bit cov_l2_params_ok, cov_car_params_ok, cov_atomics_ok, cov_pass;

  // [verilator-strip cg] covergroup cg_inst;
// [verilator-strip cg]     cp_l2_params  : coverpoint cov_l2_params_ok  { bins ok = {1'b1}; }
// [verilator-strip cg]     cp_car_params : coverpoint cov_car_params_ok  { bins ok = {1'b1}; }
// [verilator-strip cg]     cp_atomics    : coverpoint cov_atomics_ok     { bins ok = {1'b1}; }
// [verilator-strip cg]     cp_pass       : coverpoint cov_pass           { bins ok = {1'b1}; }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_inst cg = new();

  initial begin
    string amo_params[$] = '{"L2MaxReadTxns", "L2MaxWriteTxns", "AxiUserAmoMsb",
                            "AxiUserAmoLsb", "L2AmoNumCuts"};
    foreach (amo_params[idx]) begin
      if (!file_contains(L2_WRAP, amo_params[idx])) begin
        $fatal(1, "FAIL: l2_wrap.sv missing AMO parameter %s.", amo_params[idx]);
      end
    end
    cov_l2_params_ok = 1'b1;

    foreach (amo_params[idx]) begin
      if (!file_contains(CARFIELD, amo_params[idx])) begin
        $fatal(1, "FAIL: carfield.sv does not propagate AMO parameter %s.", amo_params[idx]);
      end
    end
    cov_car_params_ok = 1'b1;

    if (!file_contains(CARFIELD, "axi_riscv_atomics_structs")) begin
      $fatal(1, "FAIL: shared L2 is still missing AXI atomic support.");
    end
    cov_atomics_ok = 1'b1;

    cov_pass = 1'b1;
    /* [verilator-strip sample] */;
    $display("PASS: Shared L2 exposes and wires AMO parameters and atomics support.");
    $display("Functional coverage: %.2f%%", 0);
    $finish;
  end


  initial begin
    $dumpfile("tb_carfield_l2_amo_patch.vcd");
    $dumpvars(0);
  end

endmodule
