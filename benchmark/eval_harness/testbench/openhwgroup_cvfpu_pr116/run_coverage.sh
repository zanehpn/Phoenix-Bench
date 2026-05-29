#!/bin/bash
set -e

SNAP=../../snapshots/openhwgroup_cvfpu_pr116
CCELL=../../../common_cells/include

# Apply patch
cd ../../snapshots/openhwgroup_cvfpu_pr116
patch -p1 --forward < ../../patches/openhwgroup_cvfpu_pr116.patch || true
cd ../../testbench/openhwgroup_cvfpu_pr116

# Create coverage hierarchy config - restrict to patched module
cat > cm_hier.cfg <<'EOF'
+tree fpnew_noncomp
+module fpnew_noncomp
EOF

# Clean previous artifacts
rm -rf simv simv.daidir csrc coverage.vdb urgReport

# Compile with coverage
vcs -sverilog \
  +incdir+"$CCELL" \
  "$SNAP/src/fpnew_pkg.sv" \
  "$SNAP/src/fpnew_rounding.sv" \
  "$SNAP/src/fpnew_classifier.sv" \
  "$SNAP/src/fpnew_noncomp.sv" \
  tb_fpnew_noncomp_snan_patch.sv \
  -top tb_fpnew_noncomp_snan_patch \
  -full64 -debug_access+all \
  -cm line+cond+fsm+tgl+branch \
  -cm_dir ./coverage.vdb \
  -cm_hier ./cm_hier.cfg

# Run simulation with coverage
./simv -cm line+cond+fsm+tgl+branch -cm_dir ./coverage.vdb | tee simv.log

# Generate coverage report
urg -dir ./coverage.vdb -report ./urgReport -format text

# Restore snapshot
cd ../../snapshots/openhwgroup_cvfpu_pr116
patch -p1 -R --forward < ../../patches/openhwgroup_cvfpu_pr116.patch || true
cd ../../testbench/openhwgroup_cvfpu_pr116

echo "Coverage run complete. Check urgReport/ for results."
