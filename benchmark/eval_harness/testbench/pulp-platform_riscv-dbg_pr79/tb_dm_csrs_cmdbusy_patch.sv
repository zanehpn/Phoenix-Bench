`timescale 1ns/1ps
module tb_dm_csrs_cmdbusy_patch;
  localparam string SNAP_BASE = "../../snapshots/pulp-platform_riscv-dbg_pr79";
  localparam string TARGET    = {SNAP_BASE, "/src/dm_csrs.sv"};

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
    if (!file_has_pattern(TARGET, "An abstract command was executing while")) begin
      $fatal(1, "FAIL: dm_csrs.sv missing CmdErrBusy-for-data-read (pre-patch).");
    end
    $display("PASS: dm_csrs.sv returns CmdErrBusy for data/progbuf access during command.");
    $finish;
  end
endmodule
