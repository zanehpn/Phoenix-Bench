#!/bin/bash

SNAP=../../snapshots/pulp-platform_axi_pr245
CCELL=../../../common_cells

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  +define+COMMON_CELLS_ASSERTS_OFF \
  -assert svaext \
  +incdir+"$SNAP/include" \
  +incdir+"$CCELL/include" \
  -f ../../../common_cells/filelist.f \
  "$SNAP/src/axi_pkg.sv" \
  "$SNAP/src/axi_lite_mux.sv" \
  tb_axi_lite_mux_wchannel_patch.sv \
  -top tb_axi_lite_mux_wchannel_patch

./simv -cm line+cond+tgl+branch+fsm +assert_disable
