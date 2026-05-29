#!/bin/bash
TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
SNAP="${TESTBENCH_DIR}/../../snapshots/pulp-platform_pulp_soc_pr69"
TC_SRAM="/workspace/phoenix-bench/tech_cells_generic/src/rtl/tc_sram.sv"
cd "$TESTBENCH_DIR"
set -o pipefail
__SIMV_RC=0

rm -rf obj_dir verilator.log simv.log verilator_build.log

verilator --binary --timing --Wno-fatal \
  --Wno-WIDTH --Wno-UNOPTFLAT --Wno-BLKANDNBLK --Wno-CASEINCOMPLETE \
  --Wno-UNUSEDSIGNAL --Wno-UNUSEDPARAM --Wno-SELRANGE --Wno-IMPLICIT \
  --Wno-MULTIDRIVEN --Wno-LATCH --Wno-STMTDLY --Wno-REALCVT \
  --Wno-ENUMVALUE --Wno-PINMISSING --Wno-ASCRANGE \
  --Wno-CASEX --Wno-WIDTHCONCAT --Wno-MODDUP \
  --Wno-ASSIGNIN --Wno-VARHIDDEN --Wno-DECLFILENAME \
  --timescale 1ns/1ps \
  +define+PULP_FPGA_EMUL \
  +incdir+"${TESTBENCH_DIR}" \
  "${TESTBENCH_DIR}/xbar_tcdm_bus.sv" \
  "${TC_SRAM}" \
  "${SNAP}/rtl/pulp_soc/l2_ram_multi_bank.sv" \
  tb_l2_ram_multi_bank_verilator.sv \
  --top-module tb_l2_ram_multi_bank \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then
    echo "FAIL: Verilator build failed." >&2
    exit 1
fi

./obj_dir/simv_vlt 2>&1 | tee simv.log
__SIMV_RC=${PIPESTATUS[0]}
exit "$__SIMV_RC"
