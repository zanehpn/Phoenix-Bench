python3 testbench.py | tee simv.log

# Check the exit code of the Python testbench
RESULT=${PIPESTATUS[0]}
if [ "$RESULT" -ne 0 ]; then
    echo "FAIL: Audio channel mapping is incorrect."
else
    echo "PASS: Audio channel mapping is correct."
fi
exit "$RESULT"
