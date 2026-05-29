#!/bin/bash

SNAP="../../snapshots/pulp-platform_common_cells_pr93"

# Compile with VCS and lint checks
# The bug: stream_register uses $size(T) instead of $bits(T) for DATA_WIDTH
# $size returns the size of the first dimension only, while $bits returns total bits
# For multi-dimensional packed types, $size != $bits, causing wrong DATA_WIDTH
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  +define+VERILATOR \
  +lint=all \
  "$SNAP/src/fifo_v3.sv" \
  "$SNAP/src/deprecated/fifo_v2.sv" \
  "$SNAP/src/stream_register.sv" \
  tb_common_cells_stream_register_patch.sv \
  -top tb_common_cells_stream_register_patch \
  -o simv 2>&1 | tee compile.log

if [ $? -ne 0 ]; then
  echo "FAIL: VCS compilation failed."
fi

# Run simulation
if [ -x ./simv -cm line+cond+tgl+branch+fsm ]; then
  ./simv -cm line+cond+tgl+branch+fsm 2>&1 | tee simv.log
else
  echo "FAIL: simv not created." | tee simv.log
fi

# Check result
if grep -q "^PASS:" simv.log; then
  echo "Result: PASS"
else
  echo "Result: FAIL"
fi
