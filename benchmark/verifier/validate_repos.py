import os
import subprocess
import signal  # Required for killing process groups
import tempfile # Required for handling large outputs safely

# Configuration
SNAPSHOTS_BASE_PATH = '/workspace/phoenix-bench/data/snapshots'
TESTBENCH_BASE_PATH = '/workspace/phoenix-bench/data/testbench'
LOG_FILE = 'validation_log_base.txt'
TIMEOUT_SECONDS = 20 

def main():
    # 1. Read all snapshot directories
    try:
        snapshot_names = sorted(
            name for name in os.listdir(SNAPSHOTS_BASE_PATH)
            if os.path.isdir(os.path.join(SNAPSHOTS_BASE_PATH, name))
        )
    except FileNotFoundError:
        print(f"Error: Could not find {SNAPSHOTS_BASE_PATH}")
        return

    total_repos = len(snapshot_names)
    passed_count = 0
    
    with open(LOG_FILE, 'w') as log:
        log.write("Starting Baseline Validation Run (No Patches)...\n")

    print(f"Found {total_repos} snapshots to validate (Baseline).\n")

    for i, repo_folder_name in enumerate(snapshot_names):
        snapshot_path = os.path.join(SNAPSHOTS_BASE_PATH, repo_folder_name)
        
        current_num = i + 1
        percent_complete = (current_num / total_repos) * 100
        
        print(f"({current_num}/{total_repos}, {percent_complete:.1f}%) - {repo_folder_name}", flush=True)

        # path to run.sh
        run_script = os.path.join(TESTBENCH_BASE_PATH, repo_folder_name, 'run.sh')
        testbench_dir = os.path.join(TESTBENCH_BASE_PATH, repo_folder_name)

        # ---------------------------------------------------------
        # ROBUST EXECUTION (Popen + Process Groups + TempFile)
        # ---------------------------------------------------------
        try:
            if not os.path.exists(snapshot_path):
                log_message(f"[ERROR] Snapshot path not found: {snapshot_path}")
                print(f"Skipped (Missing snapshot): {repo_folder_name}")
                continue
            if not os.path.exists(run_script):
                log_message(f"[ERROR] run.sh not found: {run_script}")
                print(f"Skipped (Missing run.sh): {repo_folder_name}")
                continue

            # We use a temporary file for output to prevent PIPE buffer deadlocks
            # and allow us to read the output even if the process is killed.
            with tempfile.TemporaryFile(mode='w+', encoding='utf-8') as tmp_out:
                
                # start_new_session=True puts the process in a new process group.
                # This allows us to kill the shell AND any simulation tools it spawns.
                proc = subprocess.Popen(
                    ['/bin/bash', run_script],
                    cwd=testbench_dir,
                    stdout=tmp_out,
                    stderr=subprocess.STDOUT, # Merge stderr into stdout
                    start_new_session=True,
                    universal_newlines=True
                )

                timed_out = False
                try:
                    proc.wait(timeout=TIMEOUT_SECONDS)
                except subprocess.TimeoutExpired:
                    timed_out = True
                    # Kill the entire process group (PGID)
                    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                    
                # Rewind file to read output
                tmp_out.seek(0)
                console_output = tmp_out.read()

                # Logging
                if timed_out:
                    log_message(f"[TIMEOUT ERROR] {repo_folder_name}: Test timed out after {TIMEOUT_SECONDS}s.")
                    log_message(f"--- Partial Output ---\n{console_output}\n----------------------")
                    print("False (Timeout)")
                else:
                    log_message(f"--- Output for {repo_folder_name} ---\n{console_output}\n-----------------------------------")
                    
                    # Check PASS/FAIL logic
                    upper_output = console_output # Case sensitive check based on previous code? Usually upper() is safer but keeping your logic.
                    is_correct = False
                    
                    if "FAIL" in upper_output or "ERROR" in upper_output:
                        is_correct = False
                    elif "PASS" in upper_output:
                        is_correct = True
                    else:
                        log_message(f"[NO OUTCOME] {repo_folder_name}: No PASS/FAIL markers in output.")
                        print("False (No PASS/FAIL markers)")
                        continue
                    
                    print(is_correct)
                    
                    if is_correct:
                        passed_count += 1

        except Exception as e:
            log_message(f"[EXECUTION ERROR] {repo_folder_name}: {str(e)}")

    if total_repos > 0:
        pass_rate = (passed_count / total_repos) * 100
        print(f"\nBaseline Validation Complete.")
        print(f"Total Processed: {total_repos}")
        print(f"Passed (Baseline): {passed_count}")
        print(f"Pass Rate: {pass_rate:.2f}%")
    else:
        print("\nNo repositories were processed.")

def log_message(message):
    with open(LOG_FILE, 'a') as f:
        f.write(message + "\n")

if __name__ == "__main__":
    main()
