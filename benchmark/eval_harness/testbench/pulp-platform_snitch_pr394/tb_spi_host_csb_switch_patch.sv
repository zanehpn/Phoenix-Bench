`timescale 1ns/1ps
module tb_spi_host_csb_switch_patch;
  localparam string SNAP_BASE = "../../snapshots/pulp-platform_snitch_pr394";
  localparam string TARGET    = {SNAP_BASE, "/hw/vendor/lowrisc_opentitan/spi_host/rtl/spi_host_fsm.sv"};

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
    if (!file_has_pattern(TARGET, "rd_en_internal    = byte_ending & cmd_rd_en_q")) begin
      $fatal(1, "FAIL: spi_host_fsm.sv still uses WaitIdle prestall (pre-patch).");
    end
    $display("PASS: spi_host_fsm.sv uses CSBSwitch prestall state.");
    $finish;
  end
endmodule
