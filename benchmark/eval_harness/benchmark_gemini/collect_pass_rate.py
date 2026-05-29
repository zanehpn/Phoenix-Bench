import os
import subprocess
import sys
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

GEMINI_SNAPSHOTS = Path("/workspace/phoenix-bench/HDL_agent_eval/benchmark_gemini/snapshots")
TESTBENCH_ROOT = Path("/workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/testbench_verilator")
RUN_EVAL_PY = Path("/workspace/phoenix-bench/HDL_agent_eval/benchmark_gemini/run_eval.py")

def run_test(pr):
    tb_dir = TESTBENCH_ROOT / pr
    run_sh = tb_dir / "run_verilator.sh"
    
    if not run_sh.exists():
        return pr, "SKIP", "No run_verilator.sh"
    
    try:
        result = subprocess.run(
            [sys.executable, str(RUN_EVAL_PY), str(run_sh)],
            capture_output=True,
            text=True,
            timeout=300 # 5 minutes per test
        )
        if "PASS:" in result.stdout:
            return pr, "PASS", ""
        else:
            # Try to extract failure reason from build log or stdout
            build_log = tb_dir / "verilator_fixed_build.log"
            reason = ""
            if build_log.exists():
                with open(build_log, "r", errors="replace") as f:
                    last_lines = f.readlines()[-5:]
                    reason = "".join(last_lines).strip()
            if not reason:
                reason = result.stdout.splitlines()[-2:] if result.stdout else "Unknown"
                reason = " ".join(reason)
            return pr, "FAIL", reason
    except subprocess.TimeoutExpired:
        return pr, "TIMEOUT", ""
    except Exception as e:
        return pr, "ERROR", str(e)

def main():
    prs = sorted([d.name for d in GEMINI_SNAPSHOTS.iterdir() if d.is_dir()])
    print(f"Total PRs in snapshots: {len(prs)}")
    
    results = []
    # Using 8 threads for parallel execution
    with ThreadPoolExecutor(max_workers=8) as executor:
        futures = [executor.submit(run_test, pr) for pr in prs]
        for i, future in enumerate(futures):
            pr, status, reason = future.result()
            results.append((pr, status, reason))
            print(f"[{i+1}/{len(prs)}] {pr}: {status} {reason if status != 'PASS' else ''}")

    # Summary
    pass_count = sum(1 for _, status, _ in results if status == "PASS")
    fail_count = sum(1 for _, status, _ in results if status == "FAIL")
    skip_count = sum(1 for _, status, _ in results if status == "SKIP")
    timeout_count = sum(1 for _, status, _ in results if status == "TIMEOUT")
    error_count = sum(1 for _, status, _ in results if status == "ERROR")
    
    total_valid = pass_count + fail_count + timeout_count + error_count
    pass_rate = (pass_count / total_valid * 100) if total_valid > 0 else 0
    
    print("\n--- Summary ---")
    print(f"Pass:    {pass_count}")
    print(f"Fail:    {fail_count}")
    print(f"Timeout: {timeout_count}")
    print(f"Error:   {error_count}")
    print(f"Skip:    {skip_count}")
    print(f"Total:   {len(results)}")
    print(f"Pass Rate (of valid): {pass_rate:.2f}%")
    
    # Save results to file
    with open("eval_results.txt", "w") as f:
        for pr, status, reason in results:
            f.write(f"{pr}: {status} {reason}\n")
    print(f"\nDetailed results saved to eval_results.txt")

if __name__ == "__main__":
    main()
