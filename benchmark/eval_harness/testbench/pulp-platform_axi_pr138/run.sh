#!/bin/bash

cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null

SNAP=../../snapshots/pulp-platform_axi_pr138
CCELL=../../../common_cells/include

# ---------- Compile with VCS ----------------------------------------------
echo "=== Compiling with VCS ==="
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  +incdir+"$SNAP/include" \
  +incdir+"$CCELL" \
  -timescale=1ns/1ps \
  -assert svaext \
  +define+VERILATOR \
  -f ../../../common_cells/filelist.f \
  "$SNAP/src/axi_pkg.sv" \
  "$SNAP/src/axi_id_prepend.sv" \
  "$SNAP/src/axi_atop_filter.sv" \
  "$SNAP/src/axi_err_slv.sv" \
  "$SNAP/src/axi_mux.sv" \
  "$SNAP/src/axi_demux.sv" \
  "$SNAP/src/axi_xbar.sv" \
  tb_axi_xbar_cfg_localparam_patch.sv \
  -top tb_axi_xbar_cfg_localparam_patch \
  -o simv 2>&1 | tee compile.log

if [ ! -x simv ]; then
    echo "FAIL: VCS compilation failed."
fi

# ---------- Run simulation ------------------------------------------------
echo "=== Running simulation ==="
./simv -cm line+cond+tgl+branch+fsm +vcs+finish+100us 2>&1 | tee simv.log

# ---------- Check result --------------------------------------------------
echo "=== Checking results ==="
if grep -q "PASS: axi_xbar cfg_NoMstPorts localparam patch verified" simv.log; then
    echo "PASS: All tests passed - axi_xbar cfg_NoMstPorts localparam patch verified."
elif grep -q "FAIL:" simv.log; then
    echo "FAIL: Simulation reported errors."
else
    echo "FAIL: No PASS/FAIL verdict found in simulation output."
fi
