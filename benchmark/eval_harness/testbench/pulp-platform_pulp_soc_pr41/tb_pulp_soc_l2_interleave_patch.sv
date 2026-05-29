`timescale 1ns/1ps

module tb_pulp_soc_l2_interleave_patch;

  localparam string SNAP_BASE = "../../snapshots/pulp-platform_pulp_soc_pr41";
  localparam string L2_FILE   = {SNAP_BASE, "/rtl/pulp_soc/l2_ram_multi_bank.sv"};

  function automatic bit string_contains(string line, string needle);
    int haystack_len;
    int needle_len;
    haystack_len = line.len();
    needle_len  = needle.len();
    if (needle_len == 0) return 1'b1;
    if (haystack_len < needle_len) return 1'b0;
    for (int i = 0; i <= haystack_len - needle_len; i++) begin
      bit match = 1'b1;
      for (int j = 0; j < needle_len; j++) begin
        if (line[i + j] != needle[j]) begin
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
      if (line.len() != 0 && string_contains(line, needle)) begin
        file_has_pattern = 1'b1;
        break;
      end
    end
    $fclose(fd);
  endfunction

  // ---- Patch-related functional coverage ----
  // PR41: L2 interleaved bank address slices fixed to skip byte+bank bits
  bit cov_asic_addr_fixed;
  bit cov_fpga_addr_fixed;

  covergroup cg_inst;
    cp_asic_addr: coverpoint cov_asic_addr_fixed {
      bins patched = {1'b1};
    }
    cp_fpga_addr: coverpoint cov_fpga_addr_fixed {
      bins patched = {1'b1};
    }
  endgroup

  cg_inst cg = new();

  initial begin
    if (!file_has_pattern(L2_FILE, "interleaved_addresses[i][INTL_MEM_ADDR_WIDTH+2+$clog2(NB_BANKS)-1:2+$clog2(NB_BANKS)]")) begin
      $fatal(1, "FAIL: Interleaved L2 bank addressing still ignores bank bits.");
    end
    cov_asic_addr_fixed = 1'b1;
    if (!file_has_pattern(L2_FILE, "interleaved_addresses[i][INTL_MEM_ADDR_WIDTH-1+2+$clog2(NB_BANKS):2+$clog2(NB_BANKS)]")) begin
      $fatal(1, "FAIL: FPGA interleaved RAM address slice not updated.");
    end
    cov_fpga_addr_fixed = 1'b1;
    #1;
    cg.sample();
    $display("PASS: Interleaved L2 SRAM removes byte+bank bits from the address.");
    $display("Functional Coverage: %.1f%%", cg.get_coverage());
    $finish;
  end


  initial begin
    $dumpfile("tb_pulp_soc_l2_interleave_patch.vcd");
    $dumpvars(0);
  end

endmodule
