#!/bin/bash
# Testbench for microsoft/cheriot-ibex PR#81
# Verifies icache_enable_o is disabled in debug mode through simulation.

cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null

SNAPSHOT=../../snapshots/microsoft_cheriot-ibex_pr81
PRIM_DIR="$SNAPSHOT/vendor/lowrisc_ip/ip/prim/rtl"

echo "=== Compiling with VCS ==="
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  +incdir+"$PRIM_DIR" \
  +incdir+"$SNAPSHOT/rtl" \
  +define+SYNTHESIS \
  "$PRIM_DIR/prim_assert.sv" \
  "$SNAPSHOT/rtl/cheri_pkg.sv" \
  "$SNAPSHOT/rtl/ibex_pkg.sv" \
  "$SNAPSHOT/rtl/ibex_csr.sv" \
  "$SNAPSHOT/rtl/ibex_counter.sv" \
  "$SNAPSHOT/rtl/ibex_cs_registers.sv" \
  tb_ibex_cs_registers_icache_patch.sv \
  -top tb_ibex_cs_registers_icache_patch \
  -o simv 2>&1 | tee compile.log

if [ ! -x simv ]; then
    echo "FAIL: VCS compilation failed."
fi

echo "=== Running simulation ==="
./simv -cm line+cond+tgl+branch+fsm 2>&1 | tee simv.log

echo "=== Checking results ==="
if grep -q "PASS: All ibex_cs_registers" simv.log; then
    echo "PASS: icache correctly disabled in debug mode."
elif grep -q "FAIL:" simv.log; then
    echo "FAIL: icache debug mode tests failed."
else
    echo "FAIL: No PASS/FAIL verdict found in simulation output."
fi
