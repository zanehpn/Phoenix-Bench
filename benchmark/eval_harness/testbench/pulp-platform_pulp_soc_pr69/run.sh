#!/bin/bash

# Directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="/workspace/phoenix-bench"
SNAP_ROOT="${REPO_ROOT}/HDL_verified_new/snapshots/pulp-platform_pulp_soc_pr69"
TC_SRAM="${REPO_ROOT}/tech_cells_generic/src/rtl/tc_sram.sv"

# Compile the UNPATCHED (buggy) snapshot DUT with PULP_FPGA_EMUL defined.
# The bug: the unpatched code has `ifdef PULP_FPGA_EMUL guards that instantiate
# fpga_interleaved_ram / fpga_private_ram modules which do not exist as proper
# tc_sram wrappers. When PULP_FPGA_EMUL is defined, compilation fails because
# these FPGA-specific modules are not available.
# The patch removes the ifdefs so tc_sram is always used regardless of target.
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  +incdir+"${SCRIPT_DIR}" \
  +define+PULP_FPGA_EMUL \
  "${SCRIPT_DIR}/xbar_tcdm_bus.sv" \
  "${TC_SRAM}" \
  "${SNAP_ROOT}/rtl/pulp_soc/l2_ram_multi_bank.sv" \
  "${SCRIPT_DIR}/tb_l2_ram_multi_bank.sv" \
  -top tb_l2_ram_multi_bank \
  -o "${SCRIPT_DIR}/simv" \
  -l "${SCRIPT_DIR}/compile.log" 2>&1

COMPILE_RC=$?

if [ $COMPILE_RC -ne 0 ]; then
  echo "FAIL: Compilation failed (FPGA ifdef path references missing modules). See compile.log"
else
  # Run the simulation
  "${SCRIPT_DIR}/simv" -l "${SCRIPT_DIR}/simv.log" 2>&1

  # Check results
  if grep -q "RESULT: PASS" "${SCRIPT_DIR}/simv.log"; then
    echo "PASS: All tests passed."
  elif grep -q "RESULT: FAIL" "${SCRIPT_DIR}/simv.log"; then
    echo "FAIL: Some tests failed. See simv.log"
  else
    echo "FAIL: Simulation did not complete. See simv.log"
  fi
fi
