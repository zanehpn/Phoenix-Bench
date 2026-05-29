#!/bin/bash
# Count fail-to-pass test cases for each testbench
# Workflow:
#   1. Record PASS/FAIL from current (patched) simv.log
#   2. Reverse-apply patch to get buggy code
#   3. Recompile and run testbench
#   4. Record PASS/FAIL from buggy run
#   5. Restore patch
#   6. Count: test cases that FAIL on buggy but PASS on patched

BASE_DIR="/workspace/phoenix-bench/HDL_verified_new"
TB_DIR="$BASE_DIR/testbench"
SNAP_DIR="$BASE_DIR/snapshots"
PATCH_DIR="$BASE_DIR/patches"
RESULT_FILE="$BASE_DIR/fail_to_pass_results.csv"

echo "instance_id,pass_after_patch,fail_before_patch,fail_to_pass" > "$RESULT_FILE"

for tb_path in "$TB_DIR"/*/; do
    name=$(basename "$tb_path")
    patch_file="$PATCH_DIR/${name}.patch"
    snap_path="$SNAP_DIR/${name}"

    # Skip if no patch or snapshot
    if [ ! -f "$patch_file" ]; then
        echo "$name,NA,NA,NA (no patch file)"
        echo "$name,NA,NA,NA" >> "$RESULT_FILE"
        continue
    fi
    if [ ! -d "$snap_path" ]; then
        echo "$name,NA,NA,NA (no snapshot dir)"
        echo "$name,NA,NA,NA" >> "$RESULT_FILE"
        continue
    fi

    # Step 1: Run on patched code (current state), count PASS
    cd "$tb_path"
    bash run.sh > /tmp/patched_run.log 2>&1
    pass_after=$(grep -ciE "^PASS:" /tmp/patched_run.log 2>/dev/null || echo 0)
    # Also check simv.log if run.sh tees to it
    if [ -f simv.log ]; then
        pass_after2=$(grep -ciE "^PASS:" simv.log 2>/dev/null || echo 0)
        if [ "$pass_after2" -gt "$pass_after" ]; then
            pass_after=$pass_after2
        fi
    fi

    # Step 2: Reverse-apply patch
    cd "$snap_path"
    patch_ok=1
    patch -R -p1 < "$patch_file" > /tmp/patch_reverse.log 2>&1
    if [ $? -ne 0 ]; then
        # Try with --fuzz=3
        patch -R -p1 --fuzz=3 < "$patch_file" > /tmp/patch_reverse.log 2>&1
        if [ $? -ne 0 ]; then
            patch_ok=0
        fi
    fi

    if [ "$patch_ok" -eq 0 ]; then
        echo "$name,$pass_after,NA,NA (reverse patch failed)"
        echo "$name,$pass_after,NA,NA" >> "$RESULT_FILE"
        # Try to restore just in case partial apply
        patch -p1 < "$patch_file" > /dev/null 2>&1
        continue
    fi

    # Step 3: Recompile and run on buggy code
    cd "$tb_path"
    bash run.sh > /tmp/buggy_run.log 2>&1
    fail_before=$(grep -ciE "^FAIL:" /tmp/buggy_run.log 2>/dev/null || echo 0)
    if [ -f simv.log ]; then
        fail_before2=$(grep -ciE "^FAIL:" simv.log 2>/dev/null || echo 0)
        if [ "$fail_before2" -gt "$fail_before" ]; then
            fail_before=$fail_before2
        fi
    fi

    # Also count PASS on buggy (some tests may still pass)
    pass_before=$(grep -ciE "^PASS:" /tmp/buggy_run.log 2>/dev/null || echo 0)
    if [ -f simv.log ]; then
        pass_before2=$(grep -ciE "^PASS:" simv.log 2>/dev/null || echo 0)
        if [ "$pass_before2" -gt "$pass_before" ]; then
            pass_before=$pass_before2
        fi
    fi

    # Step 4: Restore patch
    cd "$snap_path"
    patch -p1 < "$patch_file" > /dev/null 2>&1

    # Step 5: Calculate fail-to-pass
    # fail_to_pass = tests that PASS after patch - tests that PASS before patch
    # (assuming same test cases run both times)
    fail_to_pass=$((pass_after - pass_before))
    if [ "$fail_to_pass" -lt 0 ]; then
        fail_to_pass=0
    fi

    echo "$name: pass_after=$pass_after, fail_before=$fail_before, pass_before=$pass_before, f2p=$fail_to_pass"
    echo "$name,$pass_after,$fail_before,$fail_to_pass" >> "$RESULT_FILE"
done

echo ""
echo "Results saved to $RESULT_FILE"
