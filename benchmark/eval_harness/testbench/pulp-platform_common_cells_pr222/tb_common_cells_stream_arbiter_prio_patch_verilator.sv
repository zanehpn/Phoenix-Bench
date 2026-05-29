`timescale 1ns/1ps

module tb_common_cells_stream_arbiter_prio_patch;

  localparam string SNAP_BASE = "../../snapshots/pulp-platform_common_cells_pr222";
  localparam string TARGET_FILE = {SNAP_BASE, "/src/stream_arbiter_flushable.sv"};

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
  // PR222: LockIn changed from 1'b1 to 1'b0 for priority arbiter
  bit cov_lockin_disabled;

  // [verilator-strip cg] covergroup cg_inst;
// [verilator-strip cg]     cp_lockin_disabled: coverpoint cov_lockin_disabled {
// [verilator-strip cg]       bins patched = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_inst cg = new();

  initial begin
    if (!file_has_pattern(TARGET_FILE, ".LockIn     (1'b0)")) begin
      $fatal(1, "FAIL: priority stream arbiter still locks rr_arb_tree decisions.");
    end
    cov_lockin_disabled = 1'b1;
    #1;
    /* [verilator-strip sample] */;
    $display("PASS: Priority stream arbiter leaves LockIn disabled to satisfy rr_arb_tree constraints.");
    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end


  initial begin
    $dumpfile("tb_common_cells_stream_arbiter_prio_patch.vcd");
    $dumpvars(0);
  end

endmodule
