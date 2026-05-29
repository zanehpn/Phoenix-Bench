`timescale 1ns/1ps

module tb_occamy_axi_include_patch;

  localparam string SNAP_ROOT = "../../snapshots/pulp-platform_snitch_pr436";
  localparam string OCCAMY_XILINX = {SNAP_ROOT, "/hw/system/occamy/src/occamy_xilinx.sv"};
  localparam string AXI_FLAT      = {SNAP_ROOT, "/hw/system/occamy/src/axi_flat.sv"};

  function automatic byte to_lower(byte ch);
    if (ch >= "A" && ch <= "Z") begin
      return ch + 8'd32;
    end
    return ch;
  endfunction

  function automatic bit string_contains_ci(string line, string needle);
    int haystack_len = line.len();
    int needle_len = needle.len();
    if (needle_len == 0) return 1'b1;
    if (haystack_len < needle_len) return 1'b0;
    for (int i = 0; i <= haystack_len - needle_len; i++) begin
      bit match = 1'b1;
      for (int j = 0; j < needle_len; j++) begin
        byte hay = to_lower(line[i + j]);
        byte nee = to_lower(needle[j]);
        if (hay != nee) begin
          match = 1'b0;
          break;
        end
      end
      if (match) return 1'b1;
    end
    return 1'b0;
  endfunction

  function automatic bit path_exists(string path);
    int fd = $fopen(path, "r");
    if (fd != 0) begin
      $fclose(fd);
      return 1'b1;
    end
    return 1'b0;
  endfunction

  function automatic bit file_contains(string path, string needle);
    int fd;
    string line;

    fd = $fopen(path, "r");
    if (fd == 0) begin
      $display("FAIL: Unable to open %s", path);
      return 1'b0;
    end

    file_contains = 1'b0;
    while (!$feof(fd)) begin
      void'($fgets(line, fd));
      if (line.len() != 0 && string_contains_ci(line, needle)) begin
        file_contains = 1'b1;
        break;
      end
    end
    $fclose(fd);
  endfunction

  // ---- Patch-related functional coverage ----
  // PR436: occamy_xilinx.sv include changed from axi_flat.svh to axi_flat.sv
  bit cov_xilinx_exists;
  bit cov_axi_flat_exists;
  bit cov_include_correct;

  covergroup cg_inst;
    cp_xilinx_exists: coverpoint cov_xilinx_exists {
      bins present = {1'b1};
    }
    cp_axi_flat_exists: coverpoint cov_axi_flat_exists {
      bins present = {1'b1};
    }
    cp_include_correct: coverpoint cov_include_correct {
      bins patched = {1'b1};
    }
  endgroup

  cg_inst cg = new();

  initial begin
    if (!path_exists(OCCAMY_XILINX)) begin
      $display("FAIL: Missing occamy_xilinx.sv at %s", OCCAMY_XILINX);
      $finish(1);
    end
    cov_xilinx_exists = 1'b1;

    if (!path_exists(AXI_FLAT)) begin
      $display("FAIL: Missing axi_flat.sv at %s", AXI_FLAT);
      $finish(1);
    end
    cov_axi_flat_exists = 1'b1;

    if (!file_contains(OCCAMY_XILINX, "`include \"axi_flat.sv\"")) begin
      $display("FAIL: occamy_xilinx.sv does not include axi_flat.sv");
      $finish(1);
    end
    cov_include_correct = 1'b1;

    cg.sample();
    $display("PASS: occamy_xilinx.sv includes axi_flat.sv and asset exists.");
    $display("Functional Coverage: cg_inst = %0.2f%%", cg.get_inst_coverage());
    $finish;
  end


  initial begin
    $dumpfile("tb_occamy_axi_include_patch.vcd");
    $dumpvars(0);
  end

endmodule
