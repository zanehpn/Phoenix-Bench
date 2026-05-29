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
  +define+SYNTHESIS= \
  +define+DV_FCOV_DISABLE \
  +incdir+../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl \
  -y ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl \
  +incdir+../../snapshots/lowRISC_ibex_pr2214/rtl \
  -y ../../snapshots/lowRISC_ibex_pr2214/rtl \
  +incdir+../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/dv/sv/dv_utils \
  -y ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/dv/sv/dv_utils \
  -y ../../snapshots/lowRISC_ibex_pr2214/dv/uvm/core_ibex/common/prim \
  -y ../../snapshots/lowRISC_ibex_pr2214/rtl \
  -y ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/dv/sv/dv_utils \
  -y ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl \
  -y ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim_generic/rtl \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_alert_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_cipher_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_count_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_esc_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_mubi_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_otp_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_pad_wrapper_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_ram_1p_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_ram_2p_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_rom_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_sha2_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_subreg_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_trivium_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_util_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_tracer_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/dv/sv/dv_utils/dv_test_status_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/dv/uvm/core_ibex/common/prim/prim_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim/rtl/prim_assert.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/dv/sv/dv_utils/dv_fcov_macros.svh \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_generic_buf.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_generic_flop.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_generic_clock_gating.sv \
  ../../snapshots/lowRISC_ibex_pr2214/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_generic_clock_mux2.sv \
  ../../snapshots/lowRISC_ibex_pr2214/dv/uvm/core_ibex/common/prim/prim_buf.sv \
  ../../snapshots/lowRISC_ibex_pr2214/dv/uvm/core_ibex/common/prim/prim_flop.sv \
  ../../snapshots/lowRISC_ibex_pr2214/dv/uvm/core_ibex/common/prim/prim_clock_gating.sv \
  ../../snapshots/lowRISC_ibex_pr2214/dv/uvm/core_ibex/common/prim/prim_clock_mux2.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_alu.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_branch_predict.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_compressed_decoder.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_controller.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_counter.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_cs_registers.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_csr.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_decoder.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_dummy_instr.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_ex_block.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_fetch_fifo.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_icache.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_id_stage.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_if_stage.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_load_store_unit.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_multdiv_fast.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_multdiv_slow.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_pmp.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_prefetch_buffer.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_register_file_ff.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_wb_stage.sv \
  ../../snapshots/lowRISC_ibex_pr2214/rtl/ibex_core.sv \
  tb_ibex_id_stage_csr_flush_patch_verilator.sv \
  --top-module tb_ibex_id_stage_csr_flush_patch \
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

SNAP=../../snapshots/lowRISC_ibex_pr2214
PRIM_RTL=$SNAP/vendor/lowrisc_ip/ip/prim/rtl
PRIM_GENERIC=$SNAP/vendor/lowrisc_ip/ip/prim_generic/rtl
PRIM_DV=$SNAP/dv/uvm/core_ibex/common/prim
DV_UTILS=$SNAP/vendor/lowrisc_ip/dv/sv/dv_utils

: # [verilator-rewrite] dropped vcs invocation

if [ $? -ne 0 ]; then
  echo "FAIL: Compilation failed"
fi

echo "--- Running simulation ---"
./obj_dir/simv_vlt +vcs+flush+all 2>&1 | tee simv.log
__SIMV_RC=${PIPESTATUS[0]}

[ -f simv.log ] || cp -f verilator.log simv.log 2>/dev/null || true
exit "$__SIMV_RC"
