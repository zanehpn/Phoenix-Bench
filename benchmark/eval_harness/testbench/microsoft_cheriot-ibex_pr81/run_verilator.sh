#!/bin/bash
# Auto-generated Verilator runner (converted from run.sh).
# Pass/fail is still determined by PASS:/FAIL: text in the log.
# Note: complex run.sh scripts with loops/multi-config VCS calls
# are flattened here — only the first VCS invocation is emulated.

TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
cd "$TESTBENCH_DIR"

rm -rf obj_dir

verilator \
  --binary \
  --timing \
  --Wno-fatal \
  --Wno-WIDTH --Wno-UNOPTFLAT --Wno-BLKANDNBLK --Wno-CASEINCOMPLETE \
  --Wno-UNUSEDSIGNAL --Wno-UNUSEDPARAM --Wno-SELRANGE --Wno-IMPLICIT \
  --Wno-MULTIDRIVEN --Wno-LATCH --Wno-STMTDLY --Wno-REALCVT \
  --Wno-ENUMVALUE --Wno-PINMISSING --Wno-ASCRANGE \
  --Wno-CASEX --Wno-WIDTHCONCAT --Wno-MODDUP \
  --Wno-ASSIGNIN --Wno-VARHIDDEN --Wno-DECLFILENAME \
  --Wno-COMBDLY --Wno-IGNOREDRETURN --Wno-LITENDIAN \
  --timescale 1ns/1ps \
  +define+SYNTHESIS \
  +incdir+../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl \
  -y ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl \
  +incdir+../../snapshots/microsoft_cheriot-ibex_pr81/rtl \
  -y ../../snapshots/microsoft_cheriot-ibex_pr81/rtl \
  -y ../../snapshots/microsoft_cheriot-ibex_pr81/rtl \
  -y ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_alert_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_cipher_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_count_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_esc_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_mubi_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_otp_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_pad_wrapper_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_ram_1p_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_ram_2p_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_rom_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_subreg_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_util_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/rtl/ibex_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/rtl/ibex_tracer_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/rtl/cheri_pkg.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/vendor/lowrisc_ip/ip/prim/rtl/prim_assert.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/rtl/ibex_csr.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/rtl/ibex_counter.sv \
  ../../snapshots/microsoft_cheriot-ibex_pr81/rtl/ibex_cs_registers.sv \
  tb_ibex_cs_registers_icache_patch_verilator.sv \
  --top-module tb_ibex_cs_registers_icache_patch \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then
  echo "FAIL: Verilator build failed." >&2
  exit 1
fi

# Wrap obj_dir/simv_vlt so any `./simv ...` or `${SIMV_NAME}` in
# the preserved shell block writes to verilator.log / simv.log.

set -o pipefail
__SIMV_RC=0
# ---- rewritten run.sh body (vcs/simv substituted) ----
#!/bin/bash
# Testbench for microsoft/cheriot-ibex PR#81
# Verifies icache_enable_o is disabled in debug mode through simulation.

cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null

SNAPSHOT=../../snapshots/microsoft_cheriot-ibex_pr81
PRIM_DIR="$SNAPSHOT/vendor/lowrisc_ip/ip/prim/rtl"

echo "=== Compiling with VCS ==="
: # [verilator-rewrite] dropped vcs invocation

if [ ! -x ./obj_dir/simv_vlt ]; then
__SIMV_RC=$?
    echo "FAIL: VCS compilation failed."
fi

echo "=== Running simulation ==="
./obj_dir/simv_vlt 2>&1 | tee simv.log
__SIMV_RC=${PIPESTATUS[0]}

[ -f simv.log ] || cp -f verilator.log simv.log 2>/dev/null || true
exit "$__SIMV_RC"
