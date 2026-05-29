SNAPSHOT=../../snapshots/lowRISC_ibex_pr1917
rm -rf simv.daidir/
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog -Xstrict \
  -assert svaext \
  +incdir+"${SNAPSHOT}"/vendor/lowrisc_ip/ip/prim/rtl \
  +incdir+"${SNAPSHOT}"/rtl \
  +incdir+"${SNAPSHOT}"/vendor/lowrisc_ip/dv/sv/dv_utils \
  ../../snapshots/lowRISC_ibex_pr1917/rtl/ibex_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr1917/rtl/ibex_tracer_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr1917/syn/rtl/prim_clock_gating.v \
  ../../snapshots/lowRISC_ibex_pr1917/vendor/lowrisc_ip/ip/prim_generic/rtl/prim_generic_buf.sv \
  ../../snapshots/lowRISC_ibex_pr1917/dv/uvm/core_ibex/common/prim/prim_buf.sv \
  ../../snapshots/lowRISC_ibex_pr1917/vendor/lowrisc_ip/ip/prim/rtl/prim_ram_1p_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr1917/vendor/lowrisc_ip/ip/prim/rtl/prim_secded_pkg.sv \
 "${SNAPSHOT}"/vendor/lowrisc_ip/ip/prim/rtl/prim_assert.sv \
 -f ../../snapshots/lowRISC_ibex_pr1917/rtl/filelist.f \
 -top ibex_top | tee vcs.log

IBEX_TOP="../../snapshots/lowRISC_ibex_pr1917/rtl/ibex_top.sv"
VCS_LOG="vcs.log"

FAIL=0

if grep -qE "else if (pending_dside_accesses_shifted\[i[[:space:]]*-[[:space:]]*1\]\.valid" "$IBEX_TOP"; then
  echo "FAIL: Found pending_dside_accesses_shifted[i - 1].valid in $IBEX_TOP"
  FAIL=1
fi

if [[ -f "$VCS_LOG" ]]; then
  if grep -q "^Error" "$VCS_LOG"; then
    echo "FAIL: Found Error in $VCS_LOG"
    FAIL=1
  fi
else
  echo "WARN: $VCS_LOG not found, skipping log check"
fi

vcs -full64 -sverilog \
  tb_ibex_pending_cov.sv \
  -top tb_ibex_pending_cov \
  -o simv_cov 2>&1 | tee compile_cov.log

./simv_cov 2>&1 | tee simv_cov.log

if [[ "$FAIL" -eq 0 ]] && grep -q "PASS:" simv_cov.log; then
  echo "PASS"
else
  echo "FAIL"
fi

