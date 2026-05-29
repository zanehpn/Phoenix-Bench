#!/bin/bash

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  ../../snapshots/pulp-platform_common_cells_pr151/src/stream_join_dynamic.sv stream_join_dynamic.sv \
  tb_stream_join.sv \
  -top tb_stream_join | tee simv.log


if [ -x ./simv ]; then
  ./simv -cm line+cond+tgl+branch+fsm | tee simv.log
else
  echo "simv not found or not executable"
fi


if grep -q "FAIL" simv.log || grep -q "Error" simv.log; then
  echo "FAIL: tb_stream_join support missing."
else
  echo "PASS: tb_stream_join is wired into the snapshots."
fi
