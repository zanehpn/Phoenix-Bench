#!/bin/bash
SNAP=../../snapshots/pulp-platform_riscv-dbg_pr123
CCELL=../../../common_cells
CCELL1=../../../tech_cells_generic

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  +incdir+"$SNAP/include" \
  +incdir+"$CCELL/include" \
  -f ../../../common_cells/filelist.f \
  "$CCELL1/src/rtl/tc_clk.sv" \
  "$CCELL1/src/deprecated/cluster_clk_cells.sv" \
  clock_mux.sv \
  "$SNAP/src/dm_pkg.sv" \
  "$SNAP/src/dm_csrs.sv" \
  "$SNAP/src/dmi_jtag_tap.sv" \
  "$SNAP/src/dmi_cdc.sv" \
  "$SNAP/src/dmi_jtag.sv" \
  tb.sv \
  -top tb_dmi_jtag_glitch_checks

./simv -cm line+cond+tgl+branch+fsm | tee simv.log
