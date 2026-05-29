#!/bin/bash

SNAPSHOT_DIR=../../snapshots/openhwgroup_core-v-xif_pr167
SRC_CORE=${SNAPSHOT_DIR}/src/core_v_xif.sv
VCS_CORE=core_v_xif_patched.sv

# -------------------------------------------------------------------
# 1. Fix unpacked array for VCS compatibility
# -------------------------------------------------------------------
cp "$SRC_CORE" "$VCS_CORE"

python3 - "$VCS_CORE" <<'PY'
import sys
from pathlib import Path

fpath = Path(sys.argv[1])
text = fpath.read_text()

needle = "logic [X_RFR_WIDTH-1:0] rs[X_NUM_RS-1:0];"
replacement = "logic [X_NUM_RS-1:0][X_RFR_WIDTH-1:0] rs;"
if needle not in text:
    raise SystemExit(f"Did not find expected register declaration in {fpath}")
text = text.replace(needle, replacement, 1)

fpath.write_text(text)
print(f"Fixed unpacked array for VCS in {fpath}")
PY

trap 'rm -f "$VCS_CORE"' EXIT

# -------------------------------------------------------------------
# 3. Compile and run
# -------------------------------------------------------------------
vcs -cm line+cond+tgl+branch+fsm -sverilog \
  "$VCS_CORE" \
  tb_core_v_xif_xmisa_patch.sv \
  -top tb_core_v_xif_xmisa_patch \
  -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

# -------------------------------------------------------------------
# 4. Check result
# -------------------------------------------------------------------
if grep -q "^PASS:" simv.log; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL"
fi
