// Coverage testbench for lowRISC/ibex PR#1917
// Bug: pending_dside_accesses_shifted[i-1] accessed when i==0 (out of bounds)
// Patch: split i==0 and i>0 into separate generate blocks (g_track_first_entry / g_track_other_entries)
// This testbench verifies the structural fix by parsing the source file.

module tb_ibex_pending_cov;

  string target_file = "../../snapshots/lowRISC_ibex_pr1917/rtl/ibex_top.sv";

  function automatic bit string_contains(string text, string pattern);
    if (pattern.len() == 0) return 1'b1;
    if (text.len() < pattern.len()) return 1'b0;
    for (int i = 0; i <= text.len() - pattern.len(); i++) begin
      if (text.substr(i, i + pattern.len() - 1) == pattern)
        return 1'b1;
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
      if (string_contains(line, pattern)) begin
        $fclose(fd);
        return 1'b1;
      end
    end
    $fclose(fd);
    return 1'b0;
  endfunction

  // Coverage signals
  bit has_first_entry_gen;
  bit has_other_entries_gen;
  bit no_bare_i_minus_1;
  bit test_completed;

  // [verilator-strip cg] covergroup cg_inst;
// [verilator-strip cg]     // Cover that g_track_first_entry generate block exists (patch addition)
// [verilator-strip cg]     cp_first_entry: coverpoint has_first_entry_gen {
// [verilator-strip cg]       bins found     = {1'b1};
// [verilator-strip cg]       ignore_bins not_found = {1'b0};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cover that g_track_other_entries generate block exists (patch addition)
// [verilator-strip cg]     cp_other_entries: coverpoint has_other_entries_gen {
// [verilator-strip cg]       bins found     = {1'b1};
// [verilator-strip cg]       ignore_bins not_found = {1'b0};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cover that the unsafe i-1 pattern in the original code is gone
// [verilator-strip cg]     cp_no_i_minus_1: coverpoint no_bare_i_minus_1 {
// [verilator-strip cg]       bins safe   = {1'b1};
// [verilator-strip cg]       ignore_bins unsafe = {1'b0};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cover test completion
// [verilator-strip cg]     cp_completed: coverpoint test_completed {
// [verilator-strip cg]       bins done = {1'b1};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cross: all structural checks must pass together
// [verilator-strip cg]     cx_all_checks: cross cp_first_entry, cp_other_entries, cp_no_i_minus_1;
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_inst cg_inst_handle = new();

  // Helper: check that the old unguarded pattern is NOT present
  function automatic bit file_has_unguarded_i_minus_1(string path);
    int fd;
    string line;
    fd = $fopen(path, "r");
    if (fd == 0) return 1'b0;
    while ($fgets(line, fd)) begin
      // The old buggy pattern: "i == 0 && !pending" or "i - 1].valid &"
      // combined in the same always_comb without generate split
      if (string_contains(line, "i == 0 && !pending_dside_accesses_shifted[i].valid") &&
          !string_contains(line, "//")) begin
        $fclose(fd);
        return 1'b1;
      end
    end
    $fclose(fd);
    return 1'b0;
  endfunction

  initial begin
    has_first_entry_gen   = file_has_pattern(target_file, "g_track_first_entry");
    has_other_entries_gen = file_has_pattern(target_file, "g_track_other_entries");
    no_bare_i_minus_1    = !file_has_unguarded_i_minus_1(target_file);

    test_completed = 1'b0;
    /* [verilator-strip sample] */;

    if (has_first_entry_gen && has_other_entries_gen && no_bare_i_minus_1) begin
      $display("PASS: ibex_top pending_dside_accesses tracking correctly split into separate generate blocks.");
      test_completed = 1'b1;
    end else begin
      if (!has_first_entry_gen)
        $display("Detail: g_track_first_entry generate block not found");
      if (!has_other_entries_gen)
        $display("Detail: g_track_other_entries generate block not found");
      if (!no_bare_i_minus_1)
        $display("Detail: unguarded i-1 access still present");
      $fatal(1, "FAIL: Patch not properly applied.");
      test_completed = 1'b1;
    end

    /* [verilator-strip sample] */;
    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end

  initial begin
    $dumpfile("tb_ibex_pending_cov.vcd");
    $dumpvars(0);
  end

endmodule
