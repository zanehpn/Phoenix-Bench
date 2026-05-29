`timescale 1ns/1ps
module tb_tcdm_arbiter_r_opc;
  localparam string SNAP_BASE = "../../snapshots/pulp-platform_pulp_soc_pr54";
  localparam string TARGET    = {SNAP_BASE, "/rtl/components/tcdm_arbiter_2x1.sv"};
  function automatic bit contains(input string hay, input string needle);
    int hl, nl;
    hl = hay.len(); nl = needle.len();
    if (nl == 0) return 1'b1;
    if (nl > hl) return 1'b0;
    for (int i = 0; i <= hl - nl; i++) begin
      bit m = 1'b1;
      for (int j = 0; j < nl; j++)
        if (hay[i+j] != needle[j]) begin m = 1'b0; break; end
      if (m) return 1'b1;
    end
    return 1'b0;
  endfunction
  function automatic bit file_has_pattern(string path, string needle);
    int fd; string line;
    file_has_pattern = 1'b0;
    fd = $fopen(path, "r");
    if (fd == 0) $fatal(1, "FAIL: %s missing", path);
    while (!$feof(fd)) begin
      void'($fgets(line, fd));
      if (line.len() != 0 && contains(line, needle)) begin
        file_has_pattern = 1'b1; break;
      end
    end
    $fclose(fd);
  endfunction
  initial begin
    if (!file_has_pattern(TARGET, "tcdm_bus_0_i.r_opc"))
      $fatal(1, "FAIL: tcdm_arbiter missing r_opc plumbing (pre-patch)");
    $display("PASS: tcdm_arbiter drives r_opc.");
    $finish;
  end
endmodule
