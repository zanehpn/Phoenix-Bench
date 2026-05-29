// tb_fpnew_cast_multi_patchcheck.sv
`timescale 1ns/1ps

module tb_fpnew_cast_int_signext_patch;
  import fpnew_pkg::*;

  // 和 DUT 内部保持一致的配置
  localparam fmt_logic_t   FpFmtConfig  = '1;
  localparam ifmt_logic_t  IntFmtConfig = '1;
  localparam int unsigned  NumPipeRegs  = 0;
  localparam pipe_config_t PipeConfig   = fpnew_pkg::BEFORE;

  localparam int unsigned WIDTH       =
      fpnew_pkg::maximum(fpnew_pkg::max_fp_width(FpFmtConfig),
                         fpnew_pkg::max_int_width(IntFmtConfig));
  localparam int unsigned NUM_FORMATS    = fpnew_pkg::NUM_FP_FORMATS;
  localparam int unsigned NUM_INT_FORMATS = fpnew_pkg::NUM_INT_FORMATS;

  // ---------------------
  // 时钟 & 复位
  // ---------------------
  logic clk;
  logic rst_ni;

  initial begin
    clk = 0;
    forever #5 clk = ~clk; // 100 MHz
  end

  initial begin
    rst_ni = 0;
    #50;
    rst_ni = 1;
  end

  // ---------------------
  // 公共输入
  // ---------------------
  logic [WIDTH-1:0]       operands;
  logic [NUM_FORMATS-1:0] is_boxed;
  roundmode_e             rnd_mode;
  operation_e             op;
  logic                   op_mod;     // 0 = signed int, 1 = unsigned
  fp_format_e             src_fmt;
  fp_format_e             dst_fmt;
  int_format_e            int_fmt;
  logic                   tag;
  logic                   mask;
  logic                   aux;

  logic in_valid;
  logic in_ready_old;
  logic in_ready_new;
  logic flush;

  logic out_ready;

  assign out_ready = 1'b1;
  assign flush     = 1'b0;

  // ---------------------
  // 输出（我们只关心 result_o）
  // ---------------------
  logic [WIDTH-1:0] result_old, result_new;
  status_t          status_old, status_new;
  logic             ext_old, ext_new;
  logic             tag_o_old, tag_o_new;
  logic             mask_o_old, mask_o_new;
  logic             aux_o_old, aux_o_new;
  logic             out_valid_old, out_valid_new;
  logic             busy_old, busy_new;

  // ---------------------
  // OLD (未打 patch 版本)
  // ---------------------
  fpnew_cast_multi #(
    .FpFmtConfig  ( FpFmtConfig  ),
    .IntFmtConfig ( IntFmtConfig ),
    .NumPipeRegs  ( NumPipeRegs  ),
    .PipeConfig   ( PipeConfig   )
  ) dut_old (
    .clk_i          ( clk            ),
    .rst_ni         ( rst_ni         ),
    .operands_i     ( operands       ),
    .is_boxed_i     ( is_boxed       ),
    .rnd_mode_i     ( rnd_mode       ),
    .op_i           ( op             ),
    .op_mod_i       ( op_mod         ),
    .src_fmt_i      ( src_fmt        ),
    .dst_fmt_i      ( dst_fmt        ),
    .int_fmt_i      ( int_fmt        ),
    .tag_i          ( tag            ),
    .mask_i         ( mask           ),
    .aux_i          ( aux            ),
    .in_valid_i     ( in_valid       ),
    .in_ready_o     ( in_ready_old   ),
    .flush_i        ( flush          ),
    .result_o       ( result_old     ),
    .status_o       ( status_old     ),
    .extension_bit_o( ext_old        ),
    .tag_o          ( tag_o_old      ),
    .mask_o         ( mask_o_old     ),
    .aux_o          ( aux_o_old      ),
    .out_valid_o    ( out_valid_old  ),
    .out_ready_i    ( out_ready      ),
    .busy_o         ( busy_old       ),
    .reg_ena_i      ( '0             )
  );

  // ---------------------
  // NEW (打完 patch 版本)
  // ---------------------
  fpnew_cast_multi_new #(
    .FpFmtConfig  ( FpFmtConfig  ),
    .IntFmtConfig ( IntFmtConfig ),
    .NumPipeRegs  ( NumPipeRegs  ),
    .PipeConfig   ( PipeConfig   )
  ) dut_new (
    .clk_i          ( clk            ),
    .rst_ni         ( rst_ni         ),
    .operands_i     ( operands       ),
    .is_boxed_i     ( is_boxed       ),
    .rnd_mode_i     ( rnd_mode       ),
    .op_i           ( op             ),
    .op_mod_i       ( op_mod         ),
    .src_fmt_i      ( src_fmt        ),
    .dst_fmt_i      ( dst_fmt        ),
    .int_fmt_i      ( int_fmt        ),
    .tag_i          ( tag            ),
    .mask_i         ( mask           ),
    .aux_i          ( aux            ),
    .in_valid_i     ( in_valid       ),
    .in_ready_o     ( in_ready_new   ),
    .flush_i        ( flush          ),
    .result_o       ( result_new     ),
    .status_o       ( status_new     ),
    .extension_bit_o( ext_new        ),
    .tag_o          ( tag_o_new      ),
    .mask_o         ( mask_o_new     ),
    .aux_o          ( aux_o_new      ),
    .out_valid_o    ( out_valid_new  ),
    .out_ready_i    ( out_ready      ),
    .busy_o         ( busy_new       ),
    .reg_ena_i      ( '0             )
  );

  // ---------------------
  // 激励：只测 F2I，重点是 sign+rounding
  // ---------------------
  initial begin : stimulus
    int i;

    // 初始值
    in_valid = 1'b0;
    operands = '0;
    is_boxed = '0;
    rnd_mode = fpnew_pkg::RNE;          // 先只测 RNE
    op       = fpnew_pkg::F2I;          // 浮点转整数
    op_mod   = 1'b0;                    // signed int
    src_fmt  = fpnew_pkg::fp_format_e'(0); // 先只用一个 FP 格式（比如最宽的那个）
    dst_fmt  = src_fmt;
    int_fmt  = fpnew_pkg::int_format_e'(0); // 从第一个 int 格式开始
    tag      = 1'b0;
    mask     = 1'b1;
    aux      = 1'b0;

    @(posedge rst_ni);
    repeat (5) @(posedge clk);

    // 1) 你可在这里塞自己手动构造的 case（比如刚好在边界上）
    // 注意：operands 要写成 src_fmt 对应的 FP bit pattern
    // 例子：某些 float 刚好 round 到负数、符号位变化的场景
    // drive_one_case(64'hXXXXXXXXXXXXXXX, fpnew_pkg::int_format_e'(0));
    // drive_one_case(64'hYYYYYYYYYYYYYYY, fpnew_pkg::int_format_e'(1));
    // ...

    for (i = 0; i < 5000; i++) begin
      // 随机选一个 int 格式（比如 INT8/16/32/64）
      int_fmt = fpnew_pkg::int_format_e'($urandom_range(NUM_INT_FORMATS-1, 0));

      // 随机选一个 FP 源格式
      src_fmt = fpnew_pkg::fp_format_e'($urandom_range(NUM_FORMATS-1, 0));
      dst_fmt = src_fmt;

      // 随机 FP bit pattern
      operands = {$urandom(), $urandom()};

      // 把对应 src_fmt 标记成 boxed，其它清 0
      is_boxed          = '0;
      is_boxed[int'(src_fmt)] = 1'b1;

      // 发送一次
      drive_one_pulse();
      @(posedge clk);
    end

    $display("Random test finished, if no mismatch printed you may add dedicated edge cases.");
    $finish;
  end

  // 发一个 in_valid 脉冲，确保两个 DUT 都 ready
  task drive_one_pulse();
    begin
      @(posedge clk);
      wait (in_ready_old && in_ready_new);
      in_valid <= 1'b1;
      @(posedge clk);
      in_valid <= 1'b0;
    end
  endtask

  // 方便插 directed case
  task drive_one_case(input logic [WIDTH-1:0] op_bits,
                      input int_format_e      fmt);
    begin
      operands = op_bits;
      int_fmt  = fmt;

      // 这里你可以必要时固定 src_fmt/int_fmt
      src_fmt = fpnew_pkg::fp_format_e'(0);
      dst_fmt = src_fmt;
      is_boxed          = '0;
      is_boxed[int'(src_fmt)] = 1'b1;

      drive_one_pulse();
      @(posedge clk);
    end
  endtask

  // ---------------------
  // 只比较整数结果 (result_o)
  // ---------------------
  always_ff @(posedge clk) begin
    if (!rst_ni) begin
      // do nothing
    end else if (out_valid_old && out_valid_new) begin
      // 只在 F2I 场景下比较（op 固定为 F2I）
      if (result_old !== result_new) begin
        $display("\n==== ERRROR: PATCH DIFFERENCE DETECTED at time %0t ====", $time);
        $display("operands = 0x%h", operands);
        $display("src_fmt  = %0d, dst_fmt = %0d, int_fmt = %0d", src_fmt, dst_fmt, int_fmt);
        $display("op_mod   = %0b (0=signed,1=unsigned)", op_mod);
        $display("OLD result = 0x%h", result_old);
        $display("NEW result = 0x%h", result_new);
        $fatal(1, "FAIL: CVFPU still trims the sign bit after F2I conversions.");
      end
    end
  end


  initial begin
    $dumpfile("tb_fpnew_cast_int_signext_patch.vcd");
    $dumpvars(0);
  end

endmodule
