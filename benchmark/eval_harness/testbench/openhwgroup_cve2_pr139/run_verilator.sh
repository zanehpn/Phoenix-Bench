#!/bin/bash
set -o pipefail

TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
cd "$TESTBENCH_DIR"

SNAP="../../snapshots/openhwgroup_cve2_pr139"
rm -rf obj_dir

verilator \
  --binary \
  --timing \
  --Wno-fatal \
  --Wno-DECLFILENAME \
  --timescale 1ns/1ps \
  "$SNAP/rtl/cve2_irq_cause.sv" \
  tb_cve2_irq_cause_verilator.sv \
  --top-module tb_cve2_irq_cause \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then
  echo "FAIL: Verilator build failed." >&2
  exit 1
fi

./obj_dir/simv_vlt 2>&1 | tee simv.log
exit "${PIPESTATUS[0]}"
