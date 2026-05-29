SNAPSHOT=../../snapshots/MiSTer-devel_MegaDrive_MiSTer_pr58/rtl
rm -rf simv.daidir
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
    -timescale=1ns/1ps \
    "${SNAPSHOT}/pad_io.sv" \
    tb_pad_io_patch.sv \
    -top tb_pad_io_patch

./simv -cm line+cond+tgl+branch+fsm