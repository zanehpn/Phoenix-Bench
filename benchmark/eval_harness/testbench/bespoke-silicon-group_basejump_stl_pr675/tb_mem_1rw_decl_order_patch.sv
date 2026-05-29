// Testbench for bespoke-silicon-group/basejump_stl PR#675
// Bug: addr_li was referenced before declaration in bsg_mem_1rw_sync_mask_write_bit_from_1r1w.sv
// Patch: moved addr_li declaration before its first use (addr_match = w_addr_r == addr_li)
// This testbench reads the source to verify declaration order, and also does a basic
// functional check by compiling and exercising the module.

`include "bsg_defines.sv"

module tb_mem_1rw_decl_order_patch;

  string target_file = "../../snapshots/bespoke-silicon-group_basejump_stl_pr675/bsg_mem/bsg_mem_1rw_sync_mask_write_bit_from_1r1w.sv";

  function automatic bit string_contains(string text, string pattern);
    if (pattern.len() == 0) return 1'b1;
    if (text.len() < pattern.len()) return 1'b0;
    for (int i = 0; i <= text.len() - pattern.len(); i++) begin
      if (text.substr(i, i + pattern.len() - 1) == pattern)
        return 1'b1;
    end
    return 1'b0;
  endfunction

  // Check that addr_li declaration comes before addr_match usage
  function automatic bit check_decl_order(string path);
    int fd;
    string line;
    int addr_li_line = -1;
    int addr_match_line = -1;
    int line_num = 0;
    fd = $fopen(path, "r");
    if (fd == 0) begin
      $display("FAIL: Unable to open %s", path);
      return 1'b0;
    end
    while ($fgets(line, fd)) begin
      line_num++;
      if (string_contains(line, "addr_li") && string_contains(line, "wire") && addr_li_line == -1)
        addr_li_line = line_num;
      if (string_contains(line, "addr_match") && string_contains(line, "wire") && addr_match_line == -1)
        addr_match_line = line_num;
    end
    $fclose(fd);
    $display("  addr_li declared at line %0d, addr_match at line %0d", addr_li_line, addr_match_line);
    return (addr_li_line > 0) && (addr_match_line > 0) && (addr_li_line < addr_match_line);
  endfunction

  // DUT instantiation for functional check
  localparam WIDTH = 8;
  localparam ELS = 4;

  logic clk, reset;
  logic [WIDTH-1:0] data_i, data_o, w_mask_i;
  logic [$clog2(ELS)-1:0] addr_i;
  logic v_i, w_i;

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  bsg_mem_1rw_sync_mask_write_bit_from_1r1w #(
    .width_p(WIDTH),
    .els_p(ELS)
  ) dut (
    .clk_i(clk),
    .reset_i(reset),
    .data_i(data_i),
    .addr_i(addr_i),
    .v_i(v_i),
    .w_mask_i(w_mask_i),
    .w_i(w_i),
    .data_o(data_o)
  );

  // Coverage signals
  bit decl_order_correct;
  bit write_tested;
  bit read_tested;

  covergroup cg_inst @(posedge clk);
    // Cover write enable
    cp_w_i: coverpoint w_i {
      bins write = {1'b1};
      bins read  = {1'b0};
    }

    // Cover valid
    cp_v_i: coverpoint v_i {
      bins active   = {1'b1};
      bins inactive = {1'b0};
    }

    // Cover address range
    cp_addr: coverpoint addr_i {
      bins addr[] = {[0:ELS-1]};
    }

    // Cover mask patterns
    cp_mask: coverpoint w_mask_i {
      bins all_ones  = {{WIDTH{1'b1}}};
      bins all_zeros = {{WIDTH{1'b0}}};
      bins partial   = default;
    }

    // Cross: write/read with address
    cx_op_addr: cross cp_w_i, cp_addr;

    // Cross: valid with write
    cx_v_w: cross cp_v_i, cp_w_i;
  endgroup

  cg_inst cg_inst_handle = new();

  initial begin
    reset = 1;
    v_i = 0;
    w_i = 0;
    data_i = 0;
    addr_i = 0;
    w_mask_i = 0;

    repeat (3) @(posedge clk);
    reset = 0;

    // Check declaration order
    decl_order_correct = check_decl_order(target_file);

    // Write to all addresses
    for (int a = 0; a < ELS; a++) begin
      @(posedge clk);
      v_i = 1;
      w_i = 1;
      addr_i = a[$clog2(ELS)-1:0];
      data_i = (a + 1) * 8'h11;
      w_mask_i = '1;
    end

    // Read from all addresses
    @(posedge clk);
    v_i = 1;
    w_i = 0;
    addr_i = 0;

    for (int a = 1; a < ELS; a++) begin
      @(posedge clk);
      addr_i = a[$clog2(ELS)-1:0];
    end

    // Partial mask write
    @(posedge clk);
    v_i = 1;
    w_i = 1;
    addr_i = 0;
    data_i = 8'hFF;
    w_mask_i = 8'h0F;

    // Exercise v_i=0 with w_i=1 (covers cx_v_w cross bin)
    @(posedge clk);
    v_i = 0;
    w_i = 1;

    @(posedge clk);
    v_i = 0;
    w_i = 0;

    repeat (3) @(posedge clk);

    $display("Functional Coverage: %.1f%%", cg_inst_handle.get_coverage());

    if (decl_order_correct) begin
      $display("PASS: addr_li is declared before addr_match (declaration order fixed).");
    end else begin
      $display("FAIL: addr_li declaration order is still incorrect.");
    end

    $finish;
  end

  initial begin
    $dumpfile("tb_mem_1rw_decl_order_patch.vcd");
    $dumpvars(0);
  end

endmodule
