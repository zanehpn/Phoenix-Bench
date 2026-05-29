`timescale 1ns/1ps
module tb_axi_pkg_width_patch;
  localparam string SNAP_BASE = "../../snapshots/pulp-platform_axi_pr293";
  localparam string TARGET    = {SNAP_BASE, "/src/axi_pkg.sv"};

  function automatic bit contains(input string hay, input string needle);
    int hl, nl;
    hl = hay.len();
    nl = needle.len();
    if (nl == 0) return 1'b1;
    if (nl > hl) return 1'b0;
    for (int i = 0; i <= hl - nl; i++) begin
      bit m = 1'b1;
      for (int j = 0; j < nl; j++) begin
        if (hay[i + j] != needle[j]) begin m = 1'b0; break; end
      end
      if (m) return 1'b1;
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
      if (line.len() != 0 && contains(line, needle)) begin
        file_has_pattern = 1'b1;
        break;
      end
    end
    $fclose(fd);
  endfunction

  initial begin
    // Fatal if pre-patch pattern STILL present (buggy state).
    if (!file_has_pattern(TARGET, "parameter int unsigned BurstWidth  = 32\'d2")) begin
      $fatal(1, "FAIL: axi_pkg.sv still parameterizes BurstWidth (pre-patch).");
    end
    $display("PASS: axi_pkg.sv removed BurstWidth = 32'd2 parameter.");
    $finish;
  end
endmodule
