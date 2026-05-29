#!/bin/bash


TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
SNAPSHOT_DIR="${TESTBENCH_DIR}/../../snapshots/openhwgroup_cv32e40s_pr254"
cd "$TESTBENCH_DIR"

# ---------------------------------------------------------------
# Define test configurations
#   Each entry is "GRANULARITY:NUM_REGIONS"
#   G=0: PMP_ADDR_WIDTH=32 (no granularity, baseline case)
#   G=1: PMP_ADDR_WIDTH=32 (bit[0] zeroed in TOR/OFF)
#   G=2: PMP_ADDR_WIDTH=31 (narrower than 32, exercises the fix)
#   G=3: PMP_ADDR_WIDTH=30 (original bug scenario)
#   Also test with multiple PMP regions
# ---------------------------------------------------------------
CONFIGS=(
  "0:1"
  "1:1"
  "2:1"
  "3:1"
  "0:4"
  "3:4"
)

TOTAL_CONFIGS=${#CONFIGS[@]}
PASSED_CONFIGS=0
FAILED_CONFIGS=0

for config in "${CONFIGS[@]}"; do
  IFS=':' read -r PMP_G PMP_R <<< "$config"
  echo ""
  echo "============================================================"
  echo "=== Configuration: PMP_GRANULARITY=${PMP_G}, PMP_NUM_REGIONS=${PMP_R}"
  echo "============================================================"

  # ---------------------------------------------------------------
  # Step 3: Compile with VCS for this configuration
  # ---------------------------------------------------------------
  echo "=== Compiling with VCS (G=${PMP_G}, R=${PMP_R}) ==="
  SIMV_NAME="simv_g${PMP_G}_r${PMP_R}"
  BUILD_LOG="simv_build_g${PMP_G}_r${PMP_R}.log"
  SIM_LOG="simv_g${PMP_G}_r${PMP_R}.log"

  set +e
  vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog -debug_access+all \
      -timescale=1ns/1ps \
      +define+COREV_ASSERT_OFF \
      +define+TB_PMP_GRANULARITY=${PMP_G} \
      +define+TB_PMP_NUM_REGIONS=${PMP_R} \
      +incdir+${SNAPSHOT_DIR}/rtl/include \
      +incdir+${SNAPSHOT_DIR}/bhv \
      +incdir+${SNAPSHOT_DIR}/bhv/include \
      +incdir+${SNAPSHOT_DIR}/sva \
      -f ${SNAPSHOT_DIR}/filelist.f \
      ${TESTBENCH_DIR}/tb_cv32e40s_pmpaddr_width_patch.sv \
      -top tb_cv32e40s_pmpaddr_width_patch \
      -o ${TESTBENCH_DIR}/${SIMV_NAME} 2>&1 | tee ${TESTBENCH_DIR}/${BUILD_LOG}
  VCS_STATUS=${PIPESTATUS[0]}

  # Check for compilation errors
  if [ $VCS_STATUS -ne 0 ] || grep -q "^Error" ${TESTBENCH_DIR}/${BUILD_LOG}; then
      echo "FAIL: Compilation failed for G=${PMP_G}, R=${PMP_R} (width mismatch bug not fixed?)"
      FAILED_CONFIGS=$((FAILED_CONFIGS + 1))
      continue
  fi
  echo "=== Compilation successful (G=${PMP_G}, R=${PMP_R}) ==="

  # ---------------------------------------------------------------
  # Step 4: Run simulation
  # ---------------------------------------------------------------
  echo "=== Running simulation (G=${PMP_G}, R=${PMP_R}) ==="
  ${TESTBENCH_DIR}/${SIMV_NAME} 2>&1 | tee ${TESTBENCH_DIR}/${SIM_LOG}

  # ---------------------------------------------------------------
  # Step 5: Check results for this configuration
  # ---------------------------------------------------------------
  if grep -q "PASS" ${TESTBENCH_DIR}/${SIM_LOG}; then
      echo "=== PASS (G=${PMP_G}, R=${PMP_R}) ==="
      PASSED_CONFIGS=$((PASSED_CONFIGS + 1))
  elif grep -q "FAIL" ${TESTBENCH_DIR}/${SIM_LOG}; then
      echo "=== FAIL (G=${PMP_G}, R=${PMP_R}) ==="
      FAILED_CONFIGS=$((FAILED_CONFIGS + 1))
  else
      echo "=== FAIL: No PASS/FAIL found in simulation output (G=${PMP_G}, R=${PMP_R}) ==="
      FAILED_CONFIGS=$((FAILED_CONFIGS + 1))
  fi
done

# ---------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------
echo ""
echo "============================================================"
echo "=== FINAL SUMMARY ==="
echo "============================================================"
echo "Configurations tested: ${TOTAL_CONFIGS}"
echo "Passed: ${PASSED_CONFIGS}"
echo "Failed: ${FAILED_CONFIGS}"
echo ""

if [ $FAILED_CONFIGS -eq 0 ]; then
    echo "PASS"
else
    echo "FAIL"
fi
