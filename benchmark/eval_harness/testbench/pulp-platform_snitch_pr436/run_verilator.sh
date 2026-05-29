#!/bin/bash
# This testbench doesn't use an HDL simulator — it checks source files via
# Python script / external tool. Dispatches to run.sh and propagates that
# exit code (success / fail) — no grep needed.
TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
cd "$TESTBENCH_DIR"
bash run.sh
RC=$?
exit "$RC"
