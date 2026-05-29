`timescale 1ns/1ps
module tb_regfile_fpga_err;
  localparam string SNAP_BASE = "../../snapshots/lowRISC_ibex_pr2241";
  localparam string TARGET    = {SNAP_BASE, "/rtl/ibex_register_file_fpga.sv"};
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
    if (!file_has_pattern(TARGET, "assign oh_raddr_a_err = 1'b0"))
      $fatal(1, "FAIL: oh_raddr_a_err not driven to 0 (pre-patch)");
    $display("PASS: oh_raddr_a_err driven to 0 when RdataMuxCheck=0.");
    $finish;
  end
endmodule
