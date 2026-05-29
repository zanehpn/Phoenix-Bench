#!/bin/bash

SNAPSHOT=../../snapshots/lowRISC_ibex_pr2269
cat > assert_defines.svh <<'MACROEOF'
`ifndef PRIM_ASSERT_DEFINES
`define PRIM_ASSERT_DEFINES
`define ASSERT(NAME_, PROP_)
`define ASSERT_INIT(NAME_, PROP_)
`endif
MACROEOF

vcs -cm line+cond+tgl+branch+fsm -sverilog +define+SYNTHESIS \
  +incdir+"${SNAPSHOT}"/vendor/lowrisc_ip/ip/prim/rtl \
  +incdir+"${SNAPSHOT}"/rtl \
  +incdir+"${SNAPSHOT}"/vendor/lowrisc_ip/ip/prim/rtl \
  assert_defines.svh \
  "${SNAPSHOT}"/rtl/ibex_pkg.sv \
  "${SNAPSHOT}"/rtl/ibex_decoder.sv \
  tb_ibex_decoder_unshfl_patch.sv \
  -top tb_ibex_decoder_unshfl_patch \
  -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: UNZIP/UNSHFL" simv.log; then
  echo "PASS: Decoder fix confirmed."
else
  echo "FAIL: Decoder fix missing."
fi
