#!/bin/bash

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  tb_carfield_l2_amo_patch.sv \
  -top tb_carfield_l2_amo_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

