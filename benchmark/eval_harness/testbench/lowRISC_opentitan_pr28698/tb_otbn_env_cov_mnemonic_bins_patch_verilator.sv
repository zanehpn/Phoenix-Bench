module tb_otbn_env_cov_mnemonic_bins_patch;

  string target_file = "../../snapshots/lowRISC_opentitan_pr28698/hw/ip/otbn/dv/uvm/env/otbn_env_cov.sv";

  function automatic string strip_ws(string s);
    string result = "";
    for (int i = 0; i < s.len(); i++) begin
      byte c = s.getc(i);
      if ((c != " ") && (c != "\t") && (c != "\n") && (c != "\r")) begin
        result = {result, c};
      end
    end
    return result;
  endfunction

  function automatic bit string_contains(string text, string pattern);
    if (pattern.len() == 0) return 1'b1;
    if (text.len() < pattern.len()) return 1'b0;
    for (int i = 0; i <= text.len() - pattern.len(); i++) begin
      if (text.substr(i, i + pattern.len() - 1) == pattern) begin
        return 1'b1;
      end
    end
    return 1'b0;
  endfunction

  function automatic bit file_has_pattern(string path, string pattern);
    int fd;
    string line;
    fd = $fopen(path, "r");
    if (fd == 0) begin
      $fatal(1, "FAIL: Unable to open %s", path);
      return 1'b0;
    end
    while ($fgets(line, fd)) begin
      string clean = strip_ws(line);
      if (string_contains(clean, pattern)) begin
        $fclose(fd);
        return 1'b1;
      end
    end
    $fclose(fd);
    return 1'b0;
  endfunction

  // Functional coverage for the mnemonic bins fix
  // Bug: DEF_MNEM_BIN used `"NAME`" (stringified) instead of NAME (variable ref)
  // This caused VCS coverage to fail because bin values had extra quotes
  bit has_variable_bins_val;
  bit has_literal_bins_val;
  bit test_completed;

  // [verilator-strip cg] covergroup cg_inst;
// [verilator-strip cg]     // Cover whether variable-based bins pattern is found (patched behavior)
// [verilator-strip cg]     cp_var_bins: coverpoint has_variable_bins_val {
// [verilator-strip cg]       bins found     = {1'b1};
// [verilator-strip cg]       // In patched state, variable bins are always found
// [verilator-strip cg]       ignore_bins ig_not_found = {1'b0};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cover whether literal-based bins pattern is found (unpatched behavior)
// [verilator-strip cg]     cp_lit_bins: coverpoint has_literal_bins_val {
// [verilator-strip cg]       // In patched state, literal bins are always absent
// [verilator-strip cg]       ignore_bins ig_found = {1'b1};
// [verilator-strip cg]       bins not_found = {1'b0};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cover test outcome
// [verilator-strip cg]     cp_test_result: coverpoint test_completed {
// [verilator-strip cg]       bins completed = {1'b1};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cross: the key bug condition - variable bins present AND literal bins absent
// [verilator-strip cg]     cx_bins_state: cross cp_var_bins, cp_lit_bins;
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_inst cg_inst_handle = new();

  initial begin
    bit has_variable_bins;
    bit has_literal_bins;
    string var_pattern  = "binsNAME={NAME}";
    string lit_pattern  = "binsNAME={\"NAME\"}";

    has_variable_bins = file_has_pattern(target_file, var_pattern);
    has_literal_bins  = file_has_pattern(target_file, lit_pattern);

    has_variable_bins_val = has_variable_bins;
    has_literal_bins_val  = has_literal_bins;
    test_completed = 1'b0;
    /* [verilator-strip sample] */;

    if (has_variable_bins && !has_literal_bins) begin
      $display("PASS: otbn_env_cov bins use the shared string variables.");
      test_completed = 1'b1;
      /* [verilator-strip sample] */;
    end else begin
      if (!has_variable_bins) begin
        $display("Detail: Missing %s pattern in %s", var_pattern, target_file);
      end
      if (has_literal_bins) begin
        $display("Detail: Found legacy literal pattern %s", lit_pattern);
      end
      $fatal(1, "FAIL: otbn_env_cov bins still stringize their names.");
      test_completed = 1'b1;
      /* [verilator-strip sample] */;
      $display("Functional Coverage: %.1f%%", 0);
      $finish;
    end

    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end


  initial begin
    $dumpfile("tb_otbn_env_cov_mnemonic_bins_patch.vcd");
    $dumpvars(0);
  end

endmodule
