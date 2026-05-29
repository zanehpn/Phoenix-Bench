#!/bin/bash
TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
SNAPSHOT_DIR="$(cd "$TESTBENCH_DIR/../../snapshots/OpenPOWERFoundation_a2o_pr18" && pwd)"
cd "$TESTBENCH_DIR"
set -o pipefail

rm -rf obj_dir verilator_build.log simv.log

verilator --binary --timing --Wno-fatal \
  --Wno-DECLFILENAME --Wno-UNUSEDSIGNAL \
  "$SNAPSHOT_DIR/dev/verilog/trilib/tri_generate_guard.v" \
  tb_a2o_generate_guard_verilator.sv \
  --top-module tb_a2o_generate_guard \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then
  echo "FAIL: Verilator build failed." >&2
  exit 1
fi

./obj_dir/simv_vlt 2>&1 | tee simv.log
exit "${PIPESTATUS[0]}"
