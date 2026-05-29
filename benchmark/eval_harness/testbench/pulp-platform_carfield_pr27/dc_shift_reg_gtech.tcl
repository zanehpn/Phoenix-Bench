# =========================
# DC compile with GTECH (default generic library)
# =========================

set TOP carfield_simple
set target_library NangateOpenCellLibrary_fast.db
set link_library  $target_library

set search_path [list \
                . \
                ../../snapshots/pulp-platform_carfield_pr27/hw/ ]

analyze -format sverilog ../../snapshots/pulp-platform_carfield_pr27/hw/rv_plic_reg_pkg.sv
analyze -format sverilog ../../snapshots/pulp-platform_carfield_pr27/hw/riscv_pkg.sv
analyze -format sverilog ../../snapshots/pulp-platform_carfield_pr27/hw/config_pkg.sv
analyze -format sverilog ../../snapshots/pulp-platform_carfield_pr27/hw/spi_host_reg_pkg.sv
analyze -format sverilog ../../snapshots/pulp-platform_carfield_pr27/hw/serial_link_single_channel_reg_pkg.sv
analyze -format sverilog ../../snapshots/pulp-platform_carfield_pr27/hw/clint_reg_pkg.sv
analyze -format sverilog ../../snapshots/pulp-platform_carfield_pr27/hw/cva6_config_pkg.sv
analyze -format sverilog ../../snapshots/pulp-platform_carfield_pr27/hw/cva65_config_pkg.sv
analyze -format sverilog ../../snapshots/pulp-platform_carfield_pr27/hw/ariane_pkg.sv
analyze -format sverilog ../../snapshots/pulp-platform_carfield_pr27/hw/cheshire_pkg.sv
analyze -format sverilog ../../snapshots/pulp-platform_carfield_pr27/hw/carfield_pkg.sv
analyze -format sverilog carfield_simple.sv
elaborate $TOP 
current_design $TOP
link

set_clock_gating_style \
  -sequential_cell latch \
  -control_point before \
  -minimum_bitwidth 1 \
  -max_fanout 32
compile_ultra -gate_clock

# report_area
# report_timing
check_design
# report_clock_gating

write -format verilog -hierarchy -output shift_reg_gtech.v

quit
