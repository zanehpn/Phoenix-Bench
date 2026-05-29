#!/bin/bash
set -o pipefail

TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
cd "$TESTBENCH_DIR"

SNAP="../../snapshots/openhwgroup_core-v-verif_pr2585"
rm -rf obj_dir

verilator \
  --binary \
  --timing \
  --Wno-fatal \
  --Wno-DECLFILENAME \
  --timescale 1ns/1ps \
  "$SNAP/cv32e40p/tb/core/cv32e40p_core_tb_wrapper.sv" \
  "$SNAP/cv32e40p/tb/core/tb_top_verilator.sv" \
  tb_corev_verilator_wrapper_verilator.sv \
  --top-module tb_corev_verilator_wrapper \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then
  echo "FAIL: Verilator build failed." >&2
  exit 1
fi

./obj_dir/simv_vlt 2>&1 | tee simv.log
exit "${PIPESTATUS[0]}"
