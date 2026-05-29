#!/bin/bash
rm -rf simv.daidir/
SNAP=../../snapshots/pulp-platform_axi_pr228
CCELL=../../../common_cells

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  +incdir+"$SNAP/include" \
  +incdir+"$CCELL/include" \
  -f ../../../common_cells/filelist.f \
  "$SNAP/src/axi_pkg.sv" \
  "$SNAP/src/axi_intf.sv" \
  "$SNAP/src/axi_lite_mux.sv" \
  tb_axi_lite_mux_intf_port_types.sv \
  -top tb_axi_lite_mux_intf_port_types

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: All 7 tests passed" simv.log; then
  echo "PASS: axi_lite_mux_intf uses the correct AXI_LITE interface types and forwards transactions."
else
  echo "FAIL: axi_lite_mux_intf tests did not all pass."
fi
