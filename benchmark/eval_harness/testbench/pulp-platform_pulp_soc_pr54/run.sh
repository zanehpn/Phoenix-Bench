#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
SNAP_DIR="$(cd "$SCRIPT_DIR/../../snapshots/pulp-platform_pulp_soc_pr54" && pwd)"
TB_FILE="$SCRIPT_DIR/tb_lint_jtag_wrap.sv"

# The DUT
DUT_FILE="$SNAP_DIR/rtl/pulp_soc/lint_jtag_wrap.sv"
INTF_FILE="$SNAP_DIR/rtl/components/pulp_interfaces.sv"

# ---------------------------------------------------------------------------
# Step 2: Compile with VCS
# ---------------------------------------------------------------------------
cd "$SCRIPT_DIR"

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  +incdir+"$SCRIPT_DIR" \
  +incdir+"$SNAP_DIR/rtl/include" \
  "$INTF_FILE" \
  "$DUT_FILE" \
  "$TB_FILE" \
  -top tb_lint_jtag_wrap \
  -o "$SCRIPT_DIR/simv_lint_jtag" \
  2>&1 | tee "$SCRIPT_DIR/compile.log"

echo "=== Compilation succeeded ==="

# ---------------------------------------------------------------------------
# Step 3: Run simulation
# ---------------------------------------------------------------------------
"$SCRIPT_DIR/simv_lint_jtag" 2>&1 | tee "$SCRIPT_DIR/simv.log"

# ---------------------------------------------------------------------------
# Step 4: Check result
# ---------------------------------------------------------------------------
if grep -q "PASS" "$SCRIPT_DIR/simv.log"; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL"
fi
