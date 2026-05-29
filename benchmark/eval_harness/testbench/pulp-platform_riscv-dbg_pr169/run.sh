#!/bin/bash

SNAP=../../snapshots/pulp-platform_riscv-dbg_pr169
CCELL=../../../common_cells
SNAP2=../../../tech_cells_generic/src/rtl/

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  +incdir+"$SNAP/include" \
  +incdir+"$CCELL/include" \
  -f ../../../common_cells/filelist.f \
  "$SNAP2/tc_clk.sv" \
  "$SNAP/src/dmi_jtag_tap.sv" \
  tb_dmi_jtag_tap_reset_patch.sv \
  -top tb_dmi_jtag_tap_reset_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: TAP is in TestLogicReset when TRST_N is asserted." simv.log; then
  echo "PASS: dmi_jtag_tap resets to TestLogicReset after TRST_N."
else
  echo "FAIL: dmi_jtag_tap reset state still incorrect."
fi
