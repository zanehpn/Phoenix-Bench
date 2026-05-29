`timescale 1ns/1ps

module tb_pulp_soc_axi_id_width_patch;

  localparam string SNAP_BASE = "../../snapshots/pulp-platform_pulp_soc_pr23";
  localparam string SOC_FILE  = {SNAP_BASE, "/rtl/pulp_soc/pulp_soc.sv"};

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

  function automatic int file_count_pattern(string path, string needle);
    int fd;
    int count;
    string line;
    count = 0;
    fd = $fopen(path, "r");
    if (fd == 0) begin
      $fatal(1, "FAIL: Unable to open %s", path);
    end
    while (!$feof(fd)) begin
      void'($fgets(line, fd));
      if (str_len(line) != 0 && contains(line, needle)) count++;
    end
    $fclose(fd);
    return count;
  endfunction

  // ---- Patch-related functional coverage ----
  // PR23: AXI_ID_WIDTH changed from AXI_ID_OUT_WIDTH to AXI_ID_IN_WIDTH for slave buses
  bit cov_id_width_fixed;

  // [verilator-strip cg] covergroup cg_inst;
// [verilator-strip cg]     cp_id_width_fixed: coverpoint cov_id_width_fixed {
// [verilator-strip cg]       bins patched = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_inst cg = new();

  initial begin
    // Patch changes two .AXI_ID_WIDTH(...) bindings from AXI_ID_OUT_WIDTH
    // to AXI_ID_IN_WIDTH, growing the count of AXI_ID_IN_WIDTH bindings.
    // Buggy file has <=1 such line; patched has >=3.
    if (file_count_pattern(SOC_FILE, "AXI_ID_IN_WIDTH   )") < 2) begin
      $fatal(1, "FAIL: s_data_slave AXI bus still uses AXI_ID_OUT_WIDTH.");
    end
    cov_id_width_fixed = 1'b1;
    /* [verilator-strip sample] */;
    $display("PASS: pulp_soc.sv configures slave/in AXI buses with AXI_ID_IN_WIDTH.");
    $display("Functional Coverage: cg_inst = %0.2f%%", 0);
    $finish;
  end


  initial begin
    $dumpfile("tb_pulp_soc_axi_id_width_patch.vcd");
    $dumpvars(0);
  end

endmodule
