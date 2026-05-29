`timescale 1ns/1ps

module tb_pulp_soc_license_patch;

  localparam string SNAP_BASE = "../../snapshots/pulp-platform_pulp_soc_pr95";
  localparam string TARGET_FILE = {SNAP_BASE, "/rtl/components/tcdm_arbiter_2x1.sv"};

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
      // Manual substring scan (Verilator 5.020 lacks string.find).
      begin
        int h_len = line.len();
        int n_len = needle.len();
        if (n_len > 0 && n_len <= h_len) begin
          for (int i = 0; i <= h_len - n_len; i++) begin
            bit match = 1'b1;
            for (int j = 0; j < n_len; j++) begin
              if (line[i + j] != needle[j]) begin match = 1'b0; break; end
            end
            if (match) begin file_has_pattern = 1'b1; break; end
          end
          if (file_has_pattern) break;
        end
      end
    end
    $fclose(fd);
  endfunction

  // ---- Patch-related functional coverage ----
  // PR95: Restricted license replaced with Solderpad Hardware License
  bit cov_no_confidential;
  bit cov_no_all_rights;
  bit cov_no_forbidden;
  bit cov_has_solderpad;

  covergroup cg_inst;
    cp_no_confidential: coverpoint cov_no_confidential {
      bins removed = {1'b1};
    }
    cp_no_all_rights: coverpoint cov_no_all_rights {
      bins removed = {1'b1};
    }
    cp_no_forbidden: coverpoint cov_no_forbidden {
      bins removed = {1'b1};
    }
    cp_has_solderpad: coverpoint cov_has_solderpad {
      bins present = {1'b1};
    }
  endgroup

  cg_inst cg = new();

  initial begin
    cov_no_confidential = !file_has_pattern(TARGET_FILE, "confidential");
    cov_no_all_rights   = !file_has_pattern(TARGET_FILE, "All rights reserved.");
    cov_no_forbidden    = !file_has_pattern(TARGET_FILE, "reuse/redistribution is strictly forbidden");

    if (!cov_no_confidential || !cov_no_all_rights || !cov_no_forbidden) begin
      $fatal(1, "FAIL: Restricted/confidential license text still present in tcdm_arbiter_2x1.sv.");
    end

    // "Solderpad Hardware License" spans two lines in the header;
    // match on the first-line substring only.
    cov_has_solderpad = file_has_pattern(TARGET_FILE, "Solderpad Hardware");
    if (!cov_has_solderpad) begin
      $fatal(1, "FAIL: Open-source Solderpad header missing from tcdm_arbiter_2x1.sv.");
    end

    cg.sample();
    $display("PASS: tcdm_arbiter_2x1.sv carries the Solderpad license header with no confidential text.");
    $display("Functional Coverage: cg_inst = %0.2f%%", cg.get_inst_coverage());
    $finish;
  end


  initial begin
    $dumpfile("tb_pulp_soc_license_patch.vcd");
    $dumpvars(0);
  end

endmodule
