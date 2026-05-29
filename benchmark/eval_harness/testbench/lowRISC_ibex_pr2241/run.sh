apt-get install -y verilator

verilator --lint-only \
  -Wwarn-UNDRIVEN \
  ../../snapshots/lowRISC_ibex_pr2241/rtl/ibex_register_file_fpga.sv 2>&1 | tee simv.log

if grep -qi "Warning-UNDRIVEN" simv.log ; then
  echo "FAIL: oh_raddr_a_err is undriven."
else
  echo "PASS: oh_raddr_a_err is not undriven."
fi

# Also run SystemVerilog simulation testbench
SNAPSHOT=../../snapshots/lowRISC_ibex_pr2241
rm -rf simv simv.daidir csrc
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog -timescale=1ns/1ps \
    +incdir+${SNAPSHOT}/vendor/lowrisc_ip/ip/prim/rtl \
    +incdir+${SNAPSHOT}/rtl \
    ${SNAPSHOT}/rtl/ibex_register_file_fpga.sv \
    tb_regfile_fpga_err.sv \
    -top tb_regfile_fpga_err 2>&1 | tee compile2.log
./simv -cm line+cond+tgl+branch+fsm 2>&1 | tee simv2.log
