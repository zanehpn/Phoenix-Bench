#!/bin/bash
TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
SNAP="${TESTBENCH_DIR}/../../snapshots/openhwgroup_core-v-xif_pr167"
cd "$TESTBENCH_DIR"
set -o pipefail
__SIMV_RC=0

VCS_CORE=core_v_xif_patched.sv
cp "${SNAP}/src/core_v_xif.sv" "$VCS_CORE"

python3 - "$VCS_CORE" <<'PY'
import sys
from pathlib import Path
fpath = Path(sys.argv[1])
text = fpath.read_text()
needle = "logic [X_RFR_WIDTH-1:0] rs[X_NUM_RS-1:0];"
replacement = "logic [X_NUM_RS-1:0][X_RFR_WIDTH-1:0] rs;"
if needle in text:
    text = text.replace(needle, replacement, 1)
    fpath.write_text(text)
PY

trap 'rm -f "${TESTBENCH_DIR}/$VCS_CORE"' EXIT

rm -rf obj_dir verilator.log simv.log verilator_build.log

verilator --binary --timing --Wno-fatal \
  --Wno-WIDTH --Wno-UNOPTFLAT --Wno-BLKANDNBLK --Wno-CASEINCOMPLETE \
  --Wno-UNUSEDSIGNAL --Wno-UNUSEDPARAM --Wno-SELRANGE --Wno-IMPLICIT \
  --Wno-MULTIDRIVEN --Wno-LATCH --Wno-STMTDLY --Wno-REALCVT \
  --Wno-ENUMVALUE --Wno-PINMISSING --Wno-ASCRANGE \
  --Wno-ASSIGNIN --Wno-VARHIDDEN --Wno-DECLFILENAME \
  --timescale 1ns/1ps \
  "$VCS_CORE" \
  tb_core_v_xif_xmisa_patch_verilator.sv \
  --top-module tb_core_v_xif_xmisa_patch \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then
    echo "FAIL: Verilator build failed." >&2
    exit 1
fi

./obj_dir/simv_vlt 2>&1 | tee simv.log
__SIMV_RC=${PIPESTATUS[0]}
exit "$__SIMV_RC"
