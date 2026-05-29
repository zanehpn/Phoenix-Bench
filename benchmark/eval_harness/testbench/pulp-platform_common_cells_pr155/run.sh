#!/bin/bash

SNAP="../../snapshots/pulp-platform_common_cells_pr155"

# Compile using the snapshot's fall_through_register.sv (buggy: uses fifo_v2)
# and only fifo_v3.sv. The buggy code references fifo_v2 which is not provided,
# so compilation should fail. The patched code uses fifo_v3 directly.
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  "$SNAP/src/fifo_v3.sv" \
  "$SNAP/src/fall_through_register.sv" \
  tb_common_cells_fall_through_register_patch.sv \
  -top tb_common_cells_fall_through_register_patch 2>&1 | tee compile.log

if [ -x ./simv -cm line+cond+tgl+branch+fsm ]; then
  ./simv -cm line+cond+tgl+branch+fsm | tee simv.log
else
  echo "FAIL: Compilation failed - fall_through_register uses deprecated fifo_v2 instead of fifo_v3." | tee simv.log
fi

if grep -q "PASS: all fall_through_register (fifo_v3) tests passed." simv.log; then
  echo "PASS: fall_through_register functional tests with fifo_v3 all passed."
else
  echo "FAIL: fall_through_register functional tests failed."
fi
