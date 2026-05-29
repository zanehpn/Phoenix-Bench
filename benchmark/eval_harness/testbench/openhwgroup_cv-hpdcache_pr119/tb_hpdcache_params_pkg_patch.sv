module tb_hpdcache_params_pkg_patch;

  import hpdcache_params_pkg::*;

  // Patch-related coverage: verify key parameters from the package compile correctly
  // The patch fixes a missing semicolon on PARAM_REFILL_FIFO_DEPTH assignment
  logic param_refill_valid;
  logic param_sets_valid;
  logic param_ways_valid;

  assign param_refill_valid = (PARAM_REFILL_FIFO_DEPTH > 0);
  assign param_sets_valid   = (PARAM_SETS > 0);
  assign param_ways_valid   = (PARAM_WAYS > 0);

  covergroup cg_params_compiled;
    option.per_instance = 1;

    cp_refill_depth: coverpoint param_refill_valid {
      bins valid = {1};
    }

    cp_sets: coverpoint param_sets_valid {
      bins valid = {1};
    }

    cp_ways: coverpoint param_ways_valid {
      bins valid = {1};
    }

    cx_all_valid: cross cp_refill_depth, cp_sets, cp_ways {
      bins all_valid = binsof(cp_refill_depth.valid) && binsof(cp_sets.valid) && binsof(cp_ways.valid);
    }
  endgroup

  cg_params_compiled cg_inst = new();

  initial begin
    cg_inst.sample();
    $display("PASS: hpdcache_params_pkg compiled (PARAM_REFILL_FIFO_DEPTH=%0d).",
             PARAM_REFILL_FIFO_DEPTH);
    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    $finish;
  end


  initial begin
    $dumpfile("tb_hpdcache_params_pkg_patch.vcd");
    $dumpvars(0);
  end

endmodule
