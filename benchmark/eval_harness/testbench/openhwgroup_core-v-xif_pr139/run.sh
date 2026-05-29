#!/bin/bash

SNAP=../../snapshots/openhwgroup_core-v-xif_pr139

# Step 1: Compile and run the patched test.sv from the snapshot to verify
# the $display string has been renamed from CORE-V-XIF to CV-X-IF
vcs -cm line+cond+tgl+branch+fsm -sverilog \
  core_v_xif_local.sv \
  "$SNAP/src/test/test.sv" \
  -top test \
  -full64 -debug_access+all \
  -o simv_test 2>&1 | tee compile_test.log

if [ $? -ne 0 ]; then
  echo "FAIL: Compilation of test.sv failed."
fi

./simv_test -cm line+cond+tgl+branch+fsm 2>&1 | tee simv_test.log

# Check that the output says "CV-X-IF" not "CORE-V-XIF"
if grep -q "CV-X-IF reference model" simv_test.log; then
  echo "PASS: test.sv $display shows CV-X-IF (renamed)"
else
  echo "FAIL: test.sv $display does not contain CV-X-IF"
fi

if grep -q "CORE-V-XIF reference model" simv_test.log; then
  echo "FAIL: test.sv still contains old CORE-V-XIF name"
fi

# Step 2: Compile and run the interface testbench
vcs -cm line+cond+tgl+branch+fsm -sverilog \
  core_v_xif_local.sv \
  tb_core_v_xif_banner_patch.sv \
  -top tb_core_v_xif_banner_patch \
  -full64 -debug_access+all \
  -o simv 2>&1 | tee compile.log

if [ $? -ne 0 ]; then
  echo "FAIL: Compilation failed."
fi

./simv -cm line+cond+tgl+branch+fsm 2>&1 | tee simv.log

# Final verdict: check BOTH steps
if grep -q "CORE-V-XIF reference model" simv_test.log 2>/dev/null; then
  echo "FAIL: test.sv still uses old CORE-V-XIF name (rename not applied)"
elif ! grep -q "CV-X-IF reference model" simv_test.log 2>/dev/null; then
  echo "FAIL: test.sv does not contain CV-X-IF reference model string"
elif grep -q "FAIL:" simv.log; then
  echo "FAIL"
elif grep -q "PASS: All tests passed." simv.log; then
  echo "PASS"
else
  echo "FAIL: No clear verdict found"
fi
