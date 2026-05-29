#!/bin/bash
set -o pipefail

TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
cd "$TESTBENCH_DIR"

SNAP="../../snapshots/AUCOHL_Lighter_pr16"
rm -rf obj_dir

verilator \
  --binary \
  --sv \
  --timing \
  --Wno-fatal \
  --Wno-DECLFILENAME \
  --timescale 1ns/1ps \
  "$SNAP/platform/sky130_fd_sc_hd/sky130_fd_sc_hd_ff_map.v" \
  tb_sky130_dffe_polarity_verilator.sv \
  --top-module tb_sky130_dffe_polarity \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then
  echo "FAIL: Verilator build failed." >&2
  exit 1
fi

./obj_dir/simv_vlt 2>&1 | tee simv.log
exit "${PIPESTATUS[0]}"
