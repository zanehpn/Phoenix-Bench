`timescale 1ns/1ps

module tb_dm_dscratch_store_patch;

  import dm::*;

  localparam int unsigned NUM_HARTS   = 1;
  localparam int unsigned BUS_WIDTH   = 32;
  localparam logic [31:0] DM_BASE     = 32'h0001_0000;
  localparam logic [4:0]  LOAD_REG    = (DM_BASE == 0) ? 5'd0 : 5'd10;

  logic clk;
  logic rst_n;

  logic                   cmd_valid;
  dm::command_t           cmd;

  logic [dm::DataCount-1:0][31:0] data_o;
  logic                           data_valid_o;
  logic                           cmderror_valid_o;
  dm::cmderr_e                    cmderror_o;
  logic                           cmdbusy_o;
  logic [NUM_HARTS-1:0]           unused_debug_req;
  logic [NUM_HARTS-1:0]           unused_halted;
  logic [NUM_HARTS-1:0]           unused_resuming;
  logic [BUS_WIDTH-1:0]           rdata_o;

  dm_mem #(
    .NrHarts(NUM_HARTS),
    .BusWidth(BUS_WIDTH),
    .DmBaseAddress(DM_BASE)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .debug_req_o(unused_debug_req),
    .hartsel_i('0),
    .haltreq_i('0),
    .resumereq_i('0),
    .clear_resumeack_i(1'b0),
    .halted_o(unused_halted),
    .resuming_o(unused_resuming),
    .progbuf_i('0),
    .data_i('0),
    .data_o(data_o),
    .data_valid_o(data_valid_o),
    .cmd_valid_i(cmd_valid),
    .cmd_i(cmd),
    .cmderror_valid_o(cmderror_valid_o),
    .cmderror_o(cmderror_o),
    .cmdbusy_o(cmdbusy_o),
    .req_i(1'b0),
    .we_i(1'b0),
    .addr_i('0),
    .wdata_i('0),
    .be_i('0),
    .rdata_o(rdata_o)
  );

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task automatic drive_access(bit write_flag);
    dm::ac_ar_cmd_t ar_cmd;
    ar_cmd              = '0;
    ar_cmd.aarsize      = 3'd2; // 32-bit access
    ar_cmd.transfer     = 1'b1;
    ar_cmd.write        = write_flag;
    ar_cmd.regno        = 16'h0000;
    cmd.cmdtype         = dm::AccessRegister;
    cmd.control         = ar_cmd;
    cmd_valid           = 1'b1;
    @(posedge clk);
    cmd_valid           = 1'b0;
    @(posedge clk);
  endtask

  task automatic expect_csrw(bit write_flag);
    logic [31:0] observed;
    logic [31:0] expected;

    drive_access(write_flag);
    observed = dut.abstract_cmd[0][31:0];
    expected = write_flag ? dm::csrw(dm::CSR_DSCRATCH1, 5'd10)
                          : dm::csrw(dm::CSR_DSCRATCH1, LOAD_REG);
    if (observed !== expected) begin
      $fatal(1,
             "FAIL: abstract_cmd[0] incorrect for write=%0d. Got 0x%08x expected 0x%08x",
             write_flag, observed, expected);
    end
  endtask

  // ---------------------------------------------------------------
  // Patch-focused covergroup: PR#90 fixes dm_mem to use csrw instead
  // of csrr for storing a0 in dscratch1 before register access.
  // Cover: write vs read access paths, correct instruction generation.
  // ---------------------------------------------------------------
  logic write_path_correct;
  logic read_path_correct;
  logic access_is_write;

  // [verilator-strip cg] covergroup cg_patch;
// [verilator-strip cg]     // Cover write access path (abstract_cmd uses csrw for write)
// [verilator-strip cg]     cp_write_path: coverpoint write_path_correct {
// [verilator-strip cg]       bins correct = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cover read access path (abstract_cmd uses csrw for read)
// [verilator-strip cg]     cp_read_path: coverpoint read_path_correct {
// [verilator-strip cg]       bins correct = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cover both access directions
// [verilator-strip cg]     cp_access_dir: coverpoint access_is_write {
// [verilator-strip cg]       bins write_access = {1'b1};
// [verilator-strip cg]       bins read_access  = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cx_dir_correct: cross cp_access_dir, cp_write_path;
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

  initial begin
    cmd_valid = 1'b0;
    cmd       = '0;
    rst_n     = 1'b0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    write_path_correct = 1'b0;
    read_path_correct  = 1'b0;

    // write path
    access_is_write = 1'b1;
    expect_csrw(1'b1);
    write_path_correct = 1'b1;
    /* [verilator-strip sample] */;

    // read path
    access_is_write = 1'b0;
    expect_csrw(1'b0);
    read_path_correct = 1'b1;
    /* [verilator-strip sample] */;

    $display("PASS: Abstract command stores a0 in dscratch1 before reuse.");
    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end


  initial begin
    $dumpfile("tb_dm_dscratch_store_patch.vcd");
    $dumpvars(0);
  end

endmodule
