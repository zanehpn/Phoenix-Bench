#!/bin/bash


SNAP=../../snapshots/openhwgroup_cve2_pr152

vcs -cm line+cond+tgl+branch+fsm -sverilog \
  +incdir+"$SNAP/rtl" \
  +incdir+"$SNAP/vendor/lowrisc_ip/ip/prim/rtl" \
  "$SNAP/rtl/cve2_pkg.sv" \
  "$SNAP/rtl/cve2_csr.sv" \
  "$SNAP/rtl/cve2_counter.sv" \
  "$SNAP/rtl/cve2_cs_registers.sv" \
  tb_cve2_vendorid_marchid_patch.sv \
  -top tb_cve2_vendorid_marchid_patch \
  -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "FAIL:" simv.log; then
  echo "FAIL: Some CSR tests did not pass. See simv.log for details."
elif grep -q "PASS:" simv.log; then
  echo "PASS: All CSR mvendorid/marchid/mimpid/mconfigptr tests passed."
else
  echo "FAIL: No PASS/FAIL markers found in output."
fi
