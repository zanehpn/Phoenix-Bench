`timescale 1ns/1ps

module tb_common_cells_onehot_to_bin_patch;

  localparam string SNAP_BASE     = "../../snapshots/pulp-platform_common_cells_pr188";
  localparam string POPCOUNT_FILE = {SNAP_BASE, "/src/popcount.sv"};

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

  function automatic bit file_has_pattern(string path, string needle);
    int fd;
    string line;
    file_has_pattern = 1'b0;
    fd = $fopen(path, "r");
    if (fd == 0) begin
      $fatal(1, "FAIL: Unable to open %s", path);
    end
    while (!$feof(fd)) begin
      void'($fgets(line, fd));
      if (str_len(line) != 0 && contains(line, needle)) begin
        file_has_pattern = 1'b1;
        break;
      end
    end
    $fclose(fd);
  endfunction

  // ---- Patch-related functional coverage ----
  // PR188: popcount simplified to flat loop, supports INPUT_WIDTH>=1
  bit cov_has_flat_loop;
  bit cov_has_flat_add;
  bit cov_has_width_check;
  bit cov_old_tree_removed;

  // [verilator-strip cg] covergroup cg_inst;
// [verilator-strip cg]     cp_flat_loop: coverpoint cov_has_flat_loop {
// [verilator-strip cg]       bins present = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_flat_add: coverpoint cov_has_flat_add {
// [verilator-strip cg]       bins present = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_width_check: coverpoint cov_has_width_check {
// [verilator-strip cg]       bins present = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_old_tree_removed: coverpoint cov_old_tree_removed {
// [verilator-strip cg]       bins removed = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_inst cg = new();

  initial begin
    bit has_flat_loop   = file_has_pattern(POPCOUNT_FILE, "for (int i = 0; i < INPUT_WIDTH; i++)");
    bit has_flat_add    = file_has_pattern(POPCOUNT_FILE, "popcount_o += data_i[i]");
    bit has_width_check = file_has_pattern(POPCOUNT_FILE, "INPUT_WIDTH must be larger or equal to 1");
    bit has_old_tree    = file_has_pattern(POPCOUNT_FILE, "padded_input") ||
                          file_has_pattern(POPCOUNT_FILE, "left_child_result") ||
                          file_has_pattern(POPCOUNT_FILE, "right_child_result");

    cov_has_flat_loop    = has_flat_loop;
    cov_has_flat_add     = has_flat_add;
    cov_has_width_check  = has_width_check;
    cov_old_tree_removed = !has_old_tree;
    #1;
    /* [verilator-strip sample] */;

    if (!has_flat_loop || !has_flat_add || !has_width_check || has_old_tree) begin
      $fatal(1, "FAIL: popcount.sv does not contain the flattened loop implementation from PR188.");
    end

    $display("PASS: popcount.sv uses flattened loop implementation with width>=1 check.");
    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end


  initial begin
    $dumpfile("tb_common_cells_onehot_to_bin_patch.vcd");
    $dumpvars(0);
  end

endmodule
