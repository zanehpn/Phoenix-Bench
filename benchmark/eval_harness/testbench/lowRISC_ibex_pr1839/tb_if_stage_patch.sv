`timescale 1ns/1ps
// Exit-code F2P tb: reads a patched source file and $fatals if the
// distinctive patched content is absent (buggy state).

module tb_if_stage_patch;
  localparam string SNAP_BASE = "../../snapshots/lowRISC_ibex_pr1839";
  localparam string TARGET    = {SNAP_BASE, "/rtl/ibex_if_stage.sv"};

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
    if (!file_has_pattern(TARGET, "if_instr_addr[1] & ~instr_is_compressed & pmp_err_if_plus2_i")) begin
      $fatal(1, "FAIL: ibex_if_stage.sv does not include pmp_err_if_plus2_i plumbing (buggy).");
    end
    $display("PASS: ibex_if_stage.sv plumbs pmp_err_if_plus2_i (patched).");
    $finish;
  end
endmodule
