import argparse
import json
import os
import sys


DEFAULT_DATASET_DIR = "/workspace/phoenix-bench/data/snapshots"
DEFAULT_ISSUES_DIR = "/workspace/phoenix-bench/data/issues"


def read_issue_text(issues_dir, instance_id):
    issue_path = os.path.join(issues_dir, instance_id)
    if not os.path.isfile(issue_path):
        return None
    with open(issue_path, "r", encoding="utf-8") as f:
        return f.read().strip()


def build_dataset(dataset_dir, issues_dir):
    entries = []
    missing = []

    for name in sorted(os.listdir(dataset_dir)):
        repo_path = os.path.join(dataset_dir, name)
        if not os.path.isdir(repo_path):
            continue

        problem_statement = read_issue_text(issues_dir, name)
        if problem_statement is None:
            missing.append(name)
            continue

        entries.append(
            {
                "instance_id": name,
                "repo": repo_path,
                "base_commit": None,
                "problem_statement": problem_statement,
            }
        )

    return entries, missing


def write_output(entries, output_path, jsonl=False):
    if jsonl:
        with open(output_path, "w", encoding="utf-8") as f:
            for entry in entries:
                f.write(json.dumps(entry) + "\n")
        return

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(entries, f, indent=2)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Build Agentless dataset JSON/JSONL from local repos and issue text."
    )
    parser.add_argument(
        "--dataset-dir",
        default=DEFAULT_DATASET_DIR,
        help="Directory containing repo subdirectories.",
    )
    parser.add_argument(
        "--issues-dir",
        default=DEFAULT_ISSUES_DIR,
        help="Directory containing issue text files named by instance_id.",
    )
    parser.add_argument(
        "--output",
        default="/workspace/phoenix-bench/Agentless/agentless_dataset.json",
        help="Output path (.json or .jsonl). Defaults next to dataset dir.",
    )
    parser.add_argument(
        "--jsonl",
        action="store_true",
        help="Write JSONL instead of JSON array.",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    dataset_dir = os.path.abspath(args.dataset_dir)
    issues_dir = os.path.abspath(args.issues_dir)
    if args.output:
        output_path = args.output
    else:
        suffix = ".jsonl" if args.jsonl else ".json"
        output_path = os.path.join(
            os.path.dirname(dataset_dir), os.path.basename(dataset_dir) + suffix
        )

    entries, missing = build_dataset(dataset_dir, issues_dir)
    write_output(entries, output_path, jsonl=args.jsonl)

    print(f"Wrote {len(entries)} entries to {output_path}")
    if missing:
        print(
            "Missing issue files for: " + ", ".join(missing),
            file=sys.stderr,
        )


if __name__ == "__main__":
    main()
