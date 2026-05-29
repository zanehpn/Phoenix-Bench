#!/bin/bash
rm -rf simv simv.daidir csrc

# Compile TB with the DUT
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
    -timescale=1ns/1ps \
    -assert svaext \
    ../../snapshots/pulp-platform_common_cells_pr188/src/popcount.sv \
    tb_common_cells_onehot_to_bin_patch.sv \
    -top tb_common_cells_onehot_to_bin_patch \
    -o simv 2>&1 | tee compile.log

if [ -x ./simv ]; then
    ./simv -cm line+cond+tgl+branch+fsm 2>&1 | tee simv.log
else
    echo "FAIL: simv not created." | tee simv.log
fi

if grep -q "PASS" simv.log && ! grep -q "FAIL" simv.log; then
    echo "PASS"
else
    echo "FAIL"
fi
