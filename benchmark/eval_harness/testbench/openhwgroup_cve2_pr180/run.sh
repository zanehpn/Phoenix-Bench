#!/bin/bash


SNAP=../../snapshots/openhwgroup_cve2_pr180
vcs -cm line+cond+tgl+branch+fsm -sverilog  +define+SYNTHESIS \
  +incdir+"$SNAP/vendor/lowrisc_ip/ip/prim/rtl" \
  +incdir+"$SNAP/vendor/lowrisc_ip/dv/sv/dv_utils" \
  +incdir+"$SNAP/vendor/lowrisc_ip/ip/prim/rtl" \
  +incdir+"$SNAP/rtl" \
  "${SNAP}/vendor/lowrisc_ip/ip/prim/rtl/prim_assert.sv" \
  "$SNAP/rtl/cve2_pkg.sv" \
  "$SNAP/rtl/cve2_decoder.sv" \
  "$SNAP/rtl/cve2_controller.sv" \
  "$SNAP/rtl/cve2_id_stage.sv" \
  tb_cve2_dret_minstret_patch.sv \
  -top tb_cve2_dret_minstret_patch \
  -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS:" simv.log; then
  echo "PASS: DRET is ignored for minstret when not in debug mode."
else
  echo "FAIL: DRET still counted towards minstret unexpectedly."
fi
