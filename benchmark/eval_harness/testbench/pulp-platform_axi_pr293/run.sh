#!/bin/bash

SNAP=../../snapshots/pulp-platform_axi_pr293

vcs -cm line+cond+tgl+branch+fsm -full64 -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  tb_axi_pkg_width_patch.sv \
  -top tb_axi_pkg_width_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log


