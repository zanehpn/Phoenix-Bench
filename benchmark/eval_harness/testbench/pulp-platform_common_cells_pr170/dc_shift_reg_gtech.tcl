# =========================
# DC compile with GTECH (default generic library)
# =========================

set TOP shift_reg

set target_library NangateOpenCellLibrary_fast.db
set link_library  $target_library

set search_path [list \
                . \
                ../../snapshots/pulp-platform_common_cells_pr170/include ]

analyze -format sverilog ../../snapshots/pulp-platform_common_cells_pr170/src/shift_reg.sv
#analyze -format sverilog top.sv
elaborate $TOP 
current_design $TOP
link

create_clock -name clk_i -period 10 [get_ports clk_i]
set_false_path -from [get_ports rst_ni]

set_clock_gating_style \
  -sequential_cell latch \
  -control_point before \
  -minimum_bitwidth 1 \
  -max_fanout 32
compile_ultra -gate_clock

report_clock_gating -verbose

# report_area
report_timing
# check_design
# report_clock_gating

write -format verilog -hierarchy -output shift_reg_gtech.v

quit
