#!/bin/bash
TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
SNAPSHOT_DIR="${TESTBENCH_DIR}/../../snapshots/pulp-platform_axi_pr74"
cd "$TESTBENCH_DIR"
set -o pipefail
__SIMV_RC=0

rm -rf obj_dir verilator.log simv.log verilator_build.log

verilator --binary --timing --Wno-fatal \
  --Wno-WIDTH --Wno-UNOPTFLAT --Wno-BLKANDNBLK --Wno-CASEINCOMPLETE \
  --Wno-UNUSEDSIGNAL --Wno-UNUSEDPARAM --Wno-SELRANGE --Wno-IMPLICIT \
  --Wno-MULTIDRIVEN --Wno-LATCH --Wno-STMTDLY --Wno-REALCVT \
  --Wno-ENUMVALUE --Wno-PINMISSING --Wno-ASCRANGE \
  --Wno-ASSIGNIN --Wno-VARHIDDEN --Wno-DECLFILENAME \
  --assert --timescale 1ns/1ps \
  +define+VERILATOR \
  +incdir+"${SNAPSHOT_DIR}/include" \
  -y "${SNAPSHOT_DIR}/include" -y "${SNAPSHOT_DIR}/src" \
  "${SNAPSHOT_DIR}/src/axi_pkg.sv" \
  "${SNAPSHOT_DIR}/src/axi_intf.sv" \
  "${TESTBENCH_DIR}/tb_axi_intf_verilator.sv" \
  --top-module tb_axi_intf \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then
    echo "FAIL: Verilator build failed." >&2
    exit 1
fi

./obj_dir/simv_vlt 2>&1 | tee simv.log
__SIMV_RC=${PIPESTATUS[0]}
cp -f simv.log verilator.log 2>/dev/null || true
exit "$__SIMV_RC"
