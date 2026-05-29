`timescale 1ns/1ps

module tb_carfield_string_param_patch;

  localparam string SNAP_BASE = "../../snapshots/pulp-platform_carfield_pr27";
  localparam string PKG_FILE  = {SNAP_BASE, "/hw/carfield_pkg.sv"};
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

  // -------------------------------------------------------------------------
  // Patch-related functional coverage
  // -------------------------------------------------------------------------
  // PR27 removes behavioral `string` parameters from carfield_pkg (which
  // cause synthesis errors) and removes them from carfield.sv instantiation.
  bit cov_no_string_rom, cov_no_string_otp, cov_no_inst_rom, cov_no_inst_otp, cov_pass;

  covergroup cg_inst;
    cp_no_string_rom : coverpoint cov_no_string_rom { bins ok = {1'b1}; }
    cp_no_string_otp : coverpoint cov_no_string_otp { bins ok = {1'b1}; }
    cp_no_inst_rom   : coverpoint cov_no_inst_rom   { bins ok = {1'b1}; }
    cp_no_inst_otp   : coverpoint cov_no_inst_otp   { bins ok = {1'b1}; }
    cp_pass          : coverpoint cov_pass           { bins ok = {1'b1}; }
  endgroup

  cg_inst cg = new();

  initial begin
    // Verify that string parameters are removed from carfield_pkg.sv
    if (file_has_pattern(PKG_FILE, "RomCtrlBootRomInitFile")) begin
      $fatal(1, "FAIL: carfield_pkg still declares RomCtrlBootRomInitFile string parameter.");
    end
    cov_no_string_rom = 1'b1;

    if (file_has_pattern(PKG_FILE, "OtpCtrlMemInitFile")) begin
      $fatal(1, "FAIL: carfield_pkg still declares OtpCtrlMemInitFile string parameter.");
    end
    cov_no_string_otp = 1'b1;

    // Verify that carfield.sv no longer passes string parameters to secure_subsystem
    if (file_has_pattern(CARFIELD, "OtpCtrlMemInitFile")) begin
      $fatal(1, "FAIL: carfield.sv still passes OtpCtrlMemInitFile to secure_subsystem.");
    end
    cov_no_inst_otp = 1'b1;

    if (file_has_pattern(CARFIELD, "RomCtrlBootRomInitFile")) begin
      $fatal(1, "FAIL: carfield.sv still passes RomCtrlBootRomInitFile to secure_subsystem.");
    end
    cov_no_inst_rom = 1'b1;

    cov_pass = 1'b1;
    cg.sample();
    $display("PASS: Behavioral string parameters removed from carfield_pkg and carfield.sv.");
    $display("Functional coverage: %.2f%%", cg.get_coverage());
    $finish;
  end

  initial begin
    $dumpfile("tb_carfield_string_param_patch.vcd");
    $dumpvars(0);
  end

endmodule
