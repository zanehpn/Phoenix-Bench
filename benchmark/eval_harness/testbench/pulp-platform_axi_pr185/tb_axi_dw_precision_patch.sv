`timescale 1ns/1ps

module tb_axi_dw_precision_patch;

  // Absolute path of the snapshots we inspect.
  localparam string SNAPSHOT_ROOT = "../../snapshots/pulp-platform_axi_pr185";

  // Return a lowercase copy of the given string without relying on simulator-specific
  // string system functions.
  function automatic string to_lower(input string s);
    string lowered;
    lowered = s;
    foreach (lowered[i]) begin
      if (lowered[i] >= "A" && lowered[i] <= "Z") begin
        lowered[i] = lowered[i] + ("a" - "A");
      end
    end
    to_lower = lowered;
  endfunction

  function automatic int str_len(input string s);
    int len;
    len = 0;
    foreach (s[i]) len++;
    return len;
  endfunction

  // Check whether `needle` occurs in `haystack`. Returns 1 if found, 0 otherwise.
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

  // Returns 1 if the given file has a line that contains both "automatic"
  // and the requested signal name. Comparison is case-insensitive.
  function automatic bit file_has_automatic_decl(string path, string signal_name);
    int fd;
    string line;
    string lowered;
    string signal_lower;

    fd = $fopen(path, "r");
    if (fd == 0) begin
      $display("FAIL: Unable to open %s for inspection.", path);
      file_has_automatic_decl = 1'bx;
      return file_has_automatic_decl;
    end

    signal_lower = to_lower(signal_name);
    file_has_automatic_decl = 1'b0;
    while (!$feof(fd)) begin
      void'($fgets(line, fd));
      lowered = to_lower(line);
      if (contains(lowered, "automatic") && contains(lowered, signal_lower)) begin
        file_has_automatic_decl = 1'b1;
        break;
      end
    end

    $fclose(fd);
  endfunction

  // -------------------------------------------------------------------------
  // Patch-related functional coverage
  // -------------------------------------------------------------------------
  // The patch removes `automatic` declarations for r_data/w_data in both
  // the downsizer and upsizer to avoid Mentor Precision latch inference.
  // We cover that each file was inspected and each signal checked.
  bit cov_downsizer_r_checked, cov_downsizer_w_checked;
  bit cov_upsizer_r_checked,   cov_upsizer_w_checked;
  bit cov_all_pass;

  covergroup cg_inst;
    cp_ds_r : coverpoint cov_downsizer_r_checked { bins checked = {1'b1}; }
    cp_ds_w : coverpoint cov_downsizer_w_checked { bins checked = {1'b1}; }
    cp_us_r : coverpoint cov_upsizer_r_checked   { bins checked = {1'b1}; }
    cp_us_w : coverpoint cov_upsizer_w_checked   { bins checked = {1'b1}; }
    cp_pass : coverpoint cov_all_pass            { bins pass    = {1'b1}; }
  endgroup

  cg_inst cg = new();

  initial begin
    string downsizer_path = {SNAPSHOT_ROOT, "/src/axi_dw_downsizer.sv"};
    string upsizer_path   = {SNAPSHOT_ROOT, "/src/axi_dw_upsizer.sv"};

    bit downsizer_r_auto = file_has_automatic_decl(downsizer_path, "r_data");
    bit downsizer_w_auto = file_has_automatic_decl(downsizer_path, "w_data");
    bit upsizer_r_auto   = file_has_automatic_decl(upsizer_path,   "r_data");
    bit upsizer_w_auto   = file_has_automatic_decl(upsizer_path,   "w_data");

    cov_downsizer_r_checked = (downsizer_r_auto !== 1'bx);
    cov_downsizer_w_checked = (downsizer_w_auto !== 1'bx);
    cov_upsizer_r_checked   = (upsizer_r_auto   !== 1'bx);
    cov_upsizer_w_checked   = (upsizer_w_auto   !== 1'bx);

    if (downsizer_r_auto === 1'bx || downsizer_w_auto === 1'bx ||
        upsizer_r_auto === 1'bx || upsizer_w_auto === 1'bx) begin
      $display("FAIL: Could not inspect all snapshots sources.");
      $finish(1);
    end

    if (downsizer_r_auto || downsizer_w_auto || upsizer_r_auto || upsizer_w_auto) begin
      $display("FAIL: axi_dw_* still declare automatic byte buffers that trigger Mentor Precision latch inference.");
      $finish(1);
    end else begin
      cov_all_pass = 1'b1;
      cg.sample();
      $display("PASS: axi_dw_* no longer use automatic byte buffers; Mentor Precision latch issue is resolved.");
      $display("Functional coverage: %.2f%%", cg.get_coverage());
      $finish;
    end
  end


  initial begin
    $dumpfile("tb_axi_dw_precision_patch.vcd");
    $dumpvars(0);
  end

endmodule
