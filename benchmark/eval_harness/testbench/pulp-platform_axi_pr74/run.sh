#!/bin/bash
# Testbench for pulp-platform/axi PR#74
# Verifies AXI_BUS_DV interface compiles and works correctly.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
SNAPSHOT_DIR="${SCRIPT_DIR}/../../snapshots/pulp-platform_axi_pr74"
TB_FILE="${SCRIPT_DIR}/tb_axi_intf.sv"

# Clean previous artifacts
rm -rf "${SCRIPT_DIR}/csrc" "${SCRIPT_DIR}/simv" "${SCRIPT_DIR}/simv.daidir" "${SCRIPT_DIR}/simv.log" "${SCRIPT_DIR}/ucli.key"

echo "=== Compiling with VCS ==="
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog +v2k \
    +incdir+"${SNAPSHOT_DIR}/include" \
    +define+VERILATOR \
    "${SNAPSHOT_DIR}/src/axi_pkg.sv" \
    "${SNAPSHOT_DIR}/src/axi_intf.sv" \
    "${TB_FILE}" \
    -o "${SCRIPT_DIR}/simv" \
    -l "${SCRIPT_DIR}/compile.log" \
    +warn=all -assert svaext \
    2>&1 | tee -a "${SCRIPT_DIR}/compile.log"

# Check compilation succeeded
if [ ! -x "${SCRIPT_DIR}/simv" ]; then
    echo "FAIL: VCS compilation failed."
fi

echo "=== Running simulation ==="
"${SCRIPT_DIR}/simv" +vcs+finish+5000 -l "${SCRIPT_DIR}/simv.log" 2>&1 | tee -a "${SCRIPT_DIR}/simv.log"

echo "=== Checking results ==="
# Check for assertion failures first (unpatched code has assertions active under VERILATOR)
if grep -qi "Assertion.*failed\|assertion.*error\|Offending" "${SCRIPT_DIR}/simv.log"; then
    echo "FAIL: Assertion fired under VERILATOR define - guards are missing (unpatched)."
elif grep -q "PASS: All AXI_BUS_DV interface tests passed" "${SCRIPT_DIR}/simv.log"; then
    echo "PASS: Simulation completed successfully."
elif grep -q "FAIL:" "${SCRIPT_DIR}/simv.log"; then
    echo "FAIL: Simulation reported errors."
else
    echo "FAIL: No PASS/FAIL verdict found in simulation output."
fi
