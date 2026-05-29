#!/bin/bash
SNAP=../../snapshots/nand2mario_nestang_pr75

vcs -cm line+cond+tgl+branch+fsm -sverilog \
  "$SNAP/src/controller_snes.v" \
  tb_controller_snes.sv \
  -timescale=1ns/1ps \
  -top tb \
  -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS:" simv.log; then
  echo "PASS: NES-style button mapping fix detected."
else
  echo "FAIL: NES-style button mapping fix missing."
fi
