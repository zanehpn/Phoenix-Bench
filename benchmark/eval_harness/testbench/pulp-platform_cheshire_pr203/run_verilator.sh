#!/bin/bash
TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
SNAPSHOT_DIR="$(cd "$TESTBENCH_DIR/../../snapshots/pulp-platform_cheshire_pr203" && pwd)"
cd "$TESTBENCH_DIR"
set -o pipefail

rm -rf obj_dir verilator_build.log simv.log

verilator --binary --timing --Wno-fatal \
  --Wno-WIDTH --Wno-UNUSEDSIGNAL --Wno-DECLFILENAME \
  --timescale 1ns/1ps \
  "$SNAPSHOT_DIR/src/cheshire_idma_wrap.sv" \
  tb_cheshire_idma_wrap_verilator.sv \
  --top-module tb_cheshire_idma_wrap \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then
  echo "FAIL: Verilator build failed." >&2
  exit 1
fi

./obj_dir/simv_vlt 2>&1 | tee simv.log
exit "${PIPESTATUS[0]}"
