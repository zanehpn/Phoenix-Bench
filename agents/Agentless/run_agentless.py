#!/usr/bin/env python3
import argparse
import os
import selectors
import subprocess
import sys
import time


def _safe_model_dir_name(model_name: str) -> str:
    return model_name.replace("/", "__")


def _build_env():
    env = os.environ.copy()
    env["OPENAI_API_BASE"] = "https://api.openai.com/v1"
    env["OPENAI_API_KEY"] = "YOUR_OPENAI_API_KEY"
    env["TREE_SITTER_VERILOG_SO"] = "/workspace/phoenix-bench/Agentless/my-languages.so"
    env["PYTHONPATH"] = f'{env.get("PYTHONPATH", "")}:{os.getcwd()}'
    env["PYTHONUNBUFFERED"] = "1"
    return env


def run_cmd(cmd, env, cwd):
    subprocess.run(cmd, env=env, cwd=cwd, check=True)


def _run_cmd_streaming(cmd, env, cwd, capture_limit=1024 * 1024):
    proc = subprocess.Popen(
        cmd,
        env=env,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
    )
    sel = selectors.DefaultSelector()
    sel.register(proc.stdout, selectors.EVENT_READ)
    sel.register(proc.stderr, selectors.EVENT_READ)
    captured = bytearray()

    while True:
        events = sel.select(timeout=1)
        if events:
            for key, _ in events:
                data = os.read(key.fileobj.fileno(), 4096)
                if not data:
                    sel.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                if key.fileobj is proc.stdout:
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
                else:
                    sys.stderr.buffer.write(data)
                    sys.stderr.buffer.flush()
                if capture_limit:
                    captured.extend(data)
                    if len(captured) > capture_limit:
                        captured = captured[-capture_limit:]
        if proc.poll() is not None and not sel.get_map():
            break

    return proc.wait(), bytes(captured)


def run_cmd_with_retry_on_read_timeout(cmd, env, cwd, max_retries):
    for attempt in range(1, max_retries + 1):
        status, output = _run_cmd_streaming(cmd, env, cwd)
        if status == 0:
            return
        if b"ReadTimeout" in output:
            if attempt < max_retries:
                print(
                    f"Step 3 hit a ReadTimeout (attempt {attempt}/{max_retries}), retrying..."
                )
                continue
        raise SystemExit(status)


def run_cmd_with_inactivity_timeout(cmd, env, cwd, timeout_seconds):
    proc = subprocess.Popen(
        cmd,
        env=env,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
    )
    sel = selectors.DefaultSelector()
    sel.register(proc.stdout, selectors.EVENT_READ)
    sel.register(proc.stderr, selectors.EVENT_READ)
    last_output = time.monotonic()

    while True:
        events = sel.select(timeout=1)
        if events:
            for key, _ in events:
                data = os.read(key.fileobj.fileno(), 4096)
                if not data:
                    sel.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                last_output = time.monotonic()
                if key.fileobj is proc.stdout:
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
                else:
                    sys.stderr.buffer.write(data)
                    sys.stderr.buffer.flush()
        else:
            if time.monotonic() - last_output > timeout_seconds:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                return 124
        if proc.poll() is not None and not sel.get_map():
            break

    return proc.wait()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model",
        type=str,
        default=os.getenv("AGENTLESS_MODEL", "gpt-5.2"),
        help="Model name for Agentless localization/repair steps.",
    )
    parser.add_argument(
        "--backend",
        type=str,
        default="openai",
        choices=["openai", "deepseek", "anthropic"],
        help="Model backend for Agentless localization/repair steps.",
    )
    args = parser.parse_args()
    model_dir = _safe_model_dir_name(args.model)

    repo_root = "/workspace/phoenix-bench/Agentless"
    os.chdir(repo_root)
    env = _build_env()

    dataset_path = "/workspace/phoenix-bench/Agentless/agentless_dataset.json"

    steps = [
        (
            "1",
            [
                "python",
                "agentless/fl/localize.py",
                "--file_level",
                "--output_folder",
                "results/hwe-bench-lite/file_level",
                "--num_threads",
                "1",
                "--skip_existing",
                "--model",
                args.model,
                "--backend",
                args.backend,
                "--dataset_path",
                dataset_path,
            ],
            False,
        ),
        (
            "2",
            [
                "python",
                "agentless/fl/localize.py",
                "--file_level",
                "--irrelevant",
                "--output_folder",
                "results/hwe-bench-lite/file_level_irrelevant",
                "--num_threads",
                "1",
                "--skip_existing",
                "--model",
                args.model,
                "--backend",
                args.backend,
                "--dataset_path",
                dataset_path,
            ],
            False,
        ),
        (
            "3",
            [
                "python",
                "agentless/fl/retrieve.py",
                "--index_type",
                "simple",
                "--filter_type",
                "given_files",
                "--filter_file",
                "results/hwe-bench-lite/file_level_irrelevant/loc_outputs.jsonl",
                "--output_folder",
                "results/hwe-bench-lite/retrievel_embedding",
                "--persist_dir",
                "embedding/hwe-bench_simple",
                "--num_threads",
                "1",
                "--dataset_path",
                dataset_path,
            ],
            False,
        ),
        (
            "4",
            [
                "python",
                "agentless/fl/combine.py",
                "--retrieval_loc_file",
                "results/hwe-bench-lite/retrievel_embedding/retrieve_locs.jsonl",
                "--model_loc_file",
                "results/hwe-bench-lite/file_level/loc_outputs.jsonl",
                "--top_n",
                "3",
                "--output_folder",
                "results/hwe-bench-lite/file_level_combined",
            ],
            False,
        ),
        (
            "5",
            [
                "python",
                "agentless/fl/localize.py",
                "--related_level",
                "--output_folder",
                "results/hwe-bench-lite/related_elements",
                "--top_n",
                "3",
                "--compress_assign",
                "--compress",
                "--start_file",
                "results/hwe-bench-lite/file_level_combined/combined_locs.jsonl",
                "--num_threads",
                "1",
                "--skip_existing",
                "--model",
                args.model,
                "--backend",
                args.backend,
                "--dataset_path",
                dataset_path,
            ],
            False,
        ),
        (
            "6",
            [
                "python",
                "agentless/fl/localize.py",
                "--fine_grain_line_level",
                "--output_folder",
                "results/hwe-bench-lite/edit_location_samples",
                "--top_n",
                "3",
                "--compress",
                "--temperature",
                "0.8",
                "--num_samples",
                "4",
                "--start_file",
                "results/hwe-bench-lite/related_elements/loc_outputs.jsonl",
                "--num_threads",
                "1",
                "--skip_existing",
                "--model",
                args.model,
                "--backend",
                args.backend,
                "--dataset_path",
                dataset_path,
            ],
            False,
        ),
        (
            "7",
            [
                "python",
                "agentless/fl/localize.py",
                "--merge",
                "--output_folder",
                "results/hwe-bench-lite/edit_location_individual",
                "--top_n",
                "3",
                "--num_samples",
                "4",
                "--start_file",
                "results/hwe-bench-lite/edit_location_samples/loc_outputs.jsonl",
                "--model",
                args.model,
                "--backend",
                args.backend,
                "--dataset_path",
                dataset_path,
            ],
            False,
        ),
        (
            "8",
            [
                "python",
                "agentless/repair/repair.py",
                "--loc_file",
                "results/hwe-bench-lite/edit_location_individual/loc_merged_0-0_outputs.jsonl",
                "--output_folder",
                f"results/hwe-bench-lite/repair_sample_verilog/{model_dir}",
                "--loc_interval",
                "--top_n=3",
                "--context_window=10",
                "--max_samples",
                "1",
                "--cot",
                "--diff_format",
                "--gen_and_process",
                "--num_threads",
                "2",
                "--model",
                args.model,
                "--backend",
                args.backend,
                "--dataset_path",
                dataset_path,
            ],
            True,
        ),
    ]

    for label, cmd, use_inactivity_timeout in steps:
        print(label)
        if label != "8":
            continue
        if label == "3":
            run_cmd_with_retry_on_read_timeout(cmd, env, repo_root, max_retries=10)
        elif use_inactivity_timeout:
            while True:
                status = run_cmd_with_inactivity_timeout(
                    cmd, env, repo_root, timeout_seconds=600
                )
                if status == 124:
                    print("Step 8 timed out after 600s of inactivity, retrying...")
                    continue
                if status != 0:
                    raise SystemExit(status)
                break
        else:
            run_cmd(cmd, env, repo_root)


if __name__ == "__main__":
    main()
