#!/bin/bash

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  tb_common_cells_stream_arbiter_prio_patch.sv \
  -top tb_common_cells_stream_arbiter_prio_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: Priority stream arbiter leaves LockIn disabled" simv.log; then
  echo "PASS: stream_arbiter priority mode no longer asserts rr_arb_tree."
else
  echo "FAIL: stream_arbiter priority mode still violates rr_arb_tree assertions."
fi
