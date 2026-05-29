module top(input logic clk, input logic rst_n);
  logic valid_i;
  logic [31:0] data_i;
  logic valid_o;
  logic [31:0] data_o;

  shift_reg #(.Depth(32'd8)) u (
    .clk_i(clk),
    .rst_ni(rst_n),
    .valid_i(valid_i),
    .data_i(data_i),
    .valid_o(valid_o),
    .data_o(data_o)
  );

  // ---- Patch-related functional coverage ----
  // PR170: shift_reg now wraps shift_reg_gated with ICG; cover valid/data activity
  covergroup cg_inst @(posedge clk);
    cp_valid_i: coverpoint valid_i {
      bins asserted   = {1'b1};
      bins deasserted = {1'b0};
    }
    cp_valid_o: coverpoint valid_o {
      bins asserted   = {1'b1};
      bins deasserted = {1'b0};
    }
    cp_rst: coverpoint rst_n {
      bins active   = {1'b0};
      bins released = {1'b1};
    }
    cp_data_i_zero: coverpoint (data_i == '0) {
      bins zero    = {1'b1};
      bins nonzero = {1'b0};
    }
    cross_valid_rst: cross cp_valid_i, cp_rst;
  endgroup

  cg_inst cg = new();
endmodule
