`timescale 1ns/1ps

import fpnew_pkg::*;

module tb_fpnew_multifmt_c_operand_patch;


  localparam int unsigned Width         = 64;
  localparam fmt_logic_t  FpFmtConfig   = '1;      
  localparam ifmt_logic_t IntFmtConfig  = '1;
  localparam bit          EnableVectors = 1'b1;

  localparam int unsigned NUM_SIMD_LANES =
      max_num_lanes(Width, FpFmtConfig, EnableVectors);

  logic                                     clk_i;
  logic                                     rst_ni;

  logic [num_operands(ADDMUL)-1:0][Width-1:0]       operands_i;
  logic [NUM_FP_FORMATS-1:0][num_operands(ADDMUL)-1:0] is_boxed_i;
  roundmode_e                                rnd_mode_i;
  operation_e                                op_i;
  logic                                      op_mod_i;
  fp_format_e                                src_fmt_i;
  fp_format_e                                dst_fmt_i;
  int_format_e                               int_fmt_i;
  logic                                      vectorial_op_i;
  logic                                      tag_i;
  logic [NUM_SIMD_LANES-1:0]                 simd_mask_i;
  logic                                      in_valid_i;
  logic                                      in_ready_o;
  logic                                      flush_i;
  logic [Width-1:0]                          result_o;
  status_t                                   status_o;
  logic                                      extension_bit_o;
  logic                                      tag_o;
  logic                                      out_valid_o;
  logic                                      out_ready_i;
  logic                                      busy_o;
  
  int src_w;
  int dst_w;
  localparam int TARGET_LANE = 1;  // Lane to inspect

  logic [Width-1:0] expected [0:2];
  // ------
  // DUT 实例
  // ------
  fpnew_opgroup_multifmt_slice #(
    .OpGroup       ( ADDMUL        ),
    .Width         ( Width         ),
    .FpFmtConfig   ( FpFmtConfig   ),
    .IntFmtConfig  ( IntFmtConfig  ),
    .EnableVectors ( EnableVectors ),
    .NumPipeRegs   ( 0             ),
    .PipeConfig    ( BEFORE        ),
    .TagType       ( logic         )
  ) dut (
    .clk_i,
    .rst_ni,
    .operands_i,
    .is_boxed_i,
    .rnd_mode_i,
    .op_i,
    .op_mod_i,
    .src_fmt_i,
    .dst_fmt_i,
    .int_fmt_i,
    .vectorial_op_i,
    .tag_i,
    .simd_mask_i,
    .in_valid_i,
    .in_ready_o,
    .flush_i,
    .result_o,
    .status_o,
    .extension_bit_o,
    .tag_o,
    .out_valid_o,
    .out_ready_i,
    .busy_o
  );

  initial begin
    clk_i = 0;
    forever #5 clk_i = ~clk_i;
  end

  initial begin
    rst_ni = 0;
    #20;
    rst_ni = 1;
  end

  initial begin
    // 默认值
    is_boxed_i      = '0;
    rnd_mode_i      = RNE;      // 随便一个就行，这里不关心运算结果
    op_i            = '0;
    op_mod_i        = '0;
    int_fmt_i       = INT32;    // 随便
    vectorial_op_i  = 1'b1;     // 开向量，这样 lane>0 有意义
    tag_i           = '0;
    simd_mask_i     = '1;
    in_valid_i      = 1'b0;
    out_ready_i     = 1'b1;
    flush_i         = 1'b0;

    @(posedge rst_ni);
    #1;

    src_fmt_i = FP16;   // 按照你实际的 enum 名字改，这里假设叫 FP16
    dst_fmt_i = FP32;   // 同上，假设叫 FP32

    operands_i[0] = 64'h1111_2222_3333_4444;
    operands_i[1] = 64'h5555_6666_7777_8888;
    operands_i[2] = 64'hAAAA_BBBB_CCCC_DDDD;

    #1;

    src_w = fp_width(src_fmt_i); 
    dst_w = fp_width(dst_fmt_i); 

    expected[0] = operands_i[0] >> (TARGET_LANE * src_w);
    expected[1] = operands_i[1] >> (TARGET_LANE * src_w);
    expected[2] = operands_i[2] >> (TARGET_LANE * dst_w);

    #1;
    $display("src_w = %0d, dst_w = %0d", src_w, dst_w);
    $display("exp[2] = 0x%h", expected[2]);

    for (int i = 0; i < 2; i++) begin
      if (dut.gen_num_lanes[TARGET_LANE].active_lane.local_operands[i] !==
          expected[i][dut.gen_num_lanes[TARGET_LANE].LANE_WIDTH-1:0]) begin
        $error("Operand %0d mismatch at lane %0d: got 0x%h, expected 0x%h",
               i, TARGET_LANE,
               dut.gen_num_lanes[TARGET_LANE].active_lane.local_operands[i],
               expected[i][dut.gen_num_lanes[TARGET_LANE].LANE_WIDTH-1:0]);
        $fatal;
      end
    end

    if (dut.gen_num_lanes[TARGET_LANE].active_lane.local_operands[2] !==
        expected[2][dut.gen_num_lanes[TARGET_LANE].LANE_WIDTH-1:0]) begin
      $error("Operand 2 mismatch at lane %0d: got 0x%h, expected (dst_fmt slice) 0x%h",
             TARGET_LANE,
             dut.gen_num_lanes[TARGET_LANE].active_lane.local_operands[2],
             expected[2][dut.gen_num_lanes[TARGET_LANE].LANE_WIDTH-1:0]);
      $fatal;
    end

    $display("TEST PASS: multifmt slice patch behaves as expected.");
    $finish;
  end


  initial begin
    $dumpfile("tb_fpnew_multifmt_c_operand_patch.vcd");
    $dumpvars(0);
  end

endmodule
