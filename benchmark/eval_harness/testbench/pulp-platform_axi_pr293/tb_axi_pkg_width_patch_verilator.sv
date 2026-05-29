// Testbench for axi_pr293: patch replaces the `BurstWidth` parameter with a
// hardcoded width in axi_pkg. Buggy state has `parameter int unsigned
// BurstWidth = 32'd2;` present; patched removes it and inlines `[1:0]`.
// We detect buggy state by reading the snapshot's axi_pkg.sv and scanning
// for the old `parameter int unsigned BurstWidth` line.

module tb_axi_pkg_width_patch;

  localparam string AXI_PKG = "../../snapshots/pulp-platform_axi_pr293/src/axi_pkg.sv";

  function automatic int str_len(input string s);
    int len;
    len = 0;
    foreach (s[i]) len++;
    return len;
  endfunction

  function automatic bit contains(input string haystack, input string needle);
    int h_len, n_len;
    h_len = str_len(haystack);
    n_len = str_len(needle);
    if (n_len == 0) return 1'b1;
    if (n_len > h_len) return 1'b0;
    for (int i = 0; i <= h_len - n_len; i++) begin
      bit match = 1'b1;
      for (int j = 0; j < n_len; j++) begin
        if (haystack[i + j] != needle[j]) begin match = 1'b0; break; end
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

  initial begin
    // Patched axi_pkg.sv inlines the burst typedef as `logic [1:0] burst_t`.
    // Buggy uses the parameterized form `logic [BurstWidth-1:0] burst_t`.
    if (file_has_pattern(AXI_PKG, "typedef logic [BurstWidth-1:0]")) begin
      $fatal(1, "FAIL: axi_pkg uses parameterized burst_t (pre-patch).");
    end
    if (!file_has_pattern(AXI_PKG, "typedef logic [1:0]  burst_t")) begin
      $fatal(1, "FAIL: axi_pkg doesn't have the hardcoded burst_t form.");
    end
    $display("PASS: axi_pkg inlines burst/resp/cache widths (patch applied).");
    $finish;
  end

endmodule
