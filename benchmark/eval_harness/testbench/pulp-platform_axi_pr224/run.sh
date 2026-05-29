#!/bin/bash

SNAP=../../snapshots/pulp-platform_axi_pr224
CCELL=../../snapshots/pulp-platform_common_cells_pr182

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  +incdir+"$SNAP/include" \
  +incdir+"$CCELL/include" \
  "$CCELL/src/cf_math_pkg.sv" \
  "$CCELL/src/lzc.sv" \
  "$CCELL/src/rr_arb_tree.sv" \
  "$CCELL/src/delta_counter.sv" \
  "$CCELL/src/fifo_v3.sv" \
  "$CCELL/src/spill_register_flushable.sv" \
  "$CCELL/src/spill_register.sv" \
  "$SNAP/src/axi_pkg.sv" \
  "$SNAP/src/axi_intf.sv" \
  "$SNAP/src/axi_lite_mux.sv" \
  "$SNAP/src/axi_demux.sv" \
  tb_axi_intf_mux_demux_patch.sv \
  -top tb_axi_intf_mux_demux_patch \
  -o simv 2>&1 | tee compile.log

if [ ! -x ./simv ]; then
    echo "FAIL: VCS compilation failed (missing params cause struct field errors)."
fi

./simv -cm line+cond+tgl+branch+fsm | tee simv.log
