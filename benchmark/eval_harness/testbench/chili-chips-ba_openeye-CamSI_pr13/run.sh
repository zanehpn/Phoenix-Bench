export HW_SRC=../../snapshots/chili-chips-ba_openeye-CamSI_pr13/1.hw

vcs -cm line+cond+tgl+branch+fsm -sverilog \
    +define+COCOTB_SIM \
    -timescale=1ns/1ps \
    unit_lib.sv \
    -f $HW_SRC/top.filelist \
    tb_i2c_reset.sv \
    -top tb_i2c_top_reset \
    -full64 -debug_access+all


  ./simv -cm line+cond+tgl+branch+fsm | tee simv.log

