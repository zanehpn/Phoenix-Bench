#!/usr/bin/env python3
import re
import sys


def parse_gated_registers(text: str) -> int:
    # Match the table line and capture the gated register count.
    match = re.search(r"Number of Gated registers\s*\|\s*(\d+)\b", text)
    if not match:
        return None
    return int(match.group(1))


def main() -> int:
    log_path = sys.argv[1] if len(sys.argv) > 1 else "run.log"
    try:
        with open(log_path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()
    except OSError as exc:
        print(f"errors: cannot read {log_path}: {exc}")
        return 2

    has_error = "Error" in content
    gated_regs = parse_gated_registers(content)

    if (not has_error) and (gated_regs is not None) and (gated_regs != 0):
        print("PASS")
        return 0

    print("FAIL")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
