#!/bin/bash

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog tb_axi_dw_precision_patch.sv -top tb_axi_dw_precision_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

