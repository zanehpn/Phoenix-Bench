vcs -cm line+cond+tgl+branch+fsm -sverilog \
    +incdir+../../snapshots/lowRISC_ibex_pr1839/vendor/lowrisc_ip/ip/prim/rtl \
    +incdir+../../snapshots/lowRISC_ibex_pr1839/rtl \
    ../../snapshots/lowRISC_ibex_pr1839/vendor/lowrisc_ip/ip/prim/rtl/prim_assert.sv \
    ../../snapshots/lowRISC_ibex_pr1839/rtl/ibex_pkg.sv \
    ../../snapshots/lowRISC_ibex_pr1839/rtl/ibex_fetch_fifo.sv \
    ../../snapshots/lowRISC_ibex_pr1839/rtl/ibex_icache.sv \
    ../../snapshots/lowRISC_ibex_pr1839/rtl/ibex_prefetch_buffer.sv \
    ../../snapshots/lowRISC_ibex_pr1839/rtl/ibex_dummy_instr.sv \
    ../../snapshots/lowRISC_ibex_pr1839/rtl/ibex_compressed_decoder.sv \
    ../../snapshots/lowRISC_ibex_pr1839/rtl/ibex_if_stage.sv \
    tb_if_stage_patch.sv \
    -top tb_if_stage_patch -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm

