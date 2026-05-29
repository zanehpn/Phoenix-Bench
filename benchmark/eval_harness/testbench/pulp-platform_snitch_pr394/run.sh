#!/bin/bash

SNAP=../../snapshots/pulp-platform_snitch_pr394
COMMON_CELLS=$SNAP/hw/vendor/pulp_platform_common_cells/include

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  +incdir+"$COMMON_CELLS" \
  "$SNAP/hw/vendor/lowrisc_opentitan/prim/rtl/prim_util_pkg.sv" \
  "$SNAP/hw/vendor/lowrisc_opentitan/spi_host/rtl/spi_host_reg_pkg.sv" \
  "$SNAP/hw/vendor/lowrisc_opentitan/spi_host/rtl/spi_host_cmd_pkg.sv" \
  "$SNAP/hw/vendor/lowrisc_opentitan/spi_host/rtl/spi_host_fsm.sv" \
  tb_spi_host_csb_switch_patch.sv \
  -top tb_spi_host_csb_switch_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log
