#!/usr/bin/env python3
"""Upload classified_issues_full.json to Hugging Face."""

from __future__ import annotations

import argparse
from pathlib import Path

from huggingface_hub import HfApi


DEFAULT_REPO_ID = "OvertureMMXXI/Phoneix-Bench"
DEFAULT_FILE = "classified_issues_full.json"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Upload classified_issues_full.json to OvertureMMXXI/Phoneix-Bench."
    )
    parser.add_argument(
        "--file",
        default=DEFAULT_FILE,
        help=f"Local file to upload. Defaults to {DEFAULT_FILE}.",
    )
    parser.add_argument(
        "--repo-id",
        default=DEFAULT_REPO_ID,
        help=f"Hugging Face repo id. Defaults to {DEFAULT_REPO_ID}.",
    )
    parser.add_argument(
        "--repo-type",
        default="dataset",
        choices=("dataset", "model", "space"),
        help="Hugging Face repository type. Defaults to dataset.",
    )
    parser.add_argument(
        "--path-in-repo",
        default=DEFAULT_FILE,
        help=f"Destination path in the repo. Defaults to {DEFAULT_FILE}.",
    )
    parser.add_argument(
        "--commit-message",
        default=f"Upload {DEFAULT_FILE}",
        help="Commit message for the upload.",
    )
    parser.add_argument(
        "--create-repo",
        action="store_true",
        help="Create the Hugging Face repo first if it does not exist.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    local_path = Path(args.file).expanduser().resolve()

    if not local_path.is_file():
        raise SystemExit(f"File not found: {local_path}")

    api = HfApi()

    if args.create_repo:
        api.create_repo(
            repo_id=args.repo_id,
            repo_type=args.repo_type,
            exist_ok=True,
        )

    upload_info = api.upload_file(
        path_or_fileobj=str(local_path),
        path_in_repo=args.path_in_repo,
        repo_id=args.repo_id,
        repo_type=args.repo_type,
        commit_message=args.commit_message,
    )

    print(f"Uploaded {local_path} to {args.repo_id}/{args.path_in_repo}")
    print(upload_info)


if __name__ == "__main__":
    main()
