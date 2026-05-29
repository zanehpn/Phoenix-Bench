#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from pathlib import Path

file_a = Path("../../snapshots/pulp-platform_snitch_pr436/hw/system/occamy/src/occamy_xilinx.sv")
file_b = Path("occamy_xilinx.sv")

if not file_a.exists():
    print(f"FAIL: {file_a} does not exist")
    exit(1)

if not file_b.exists():
    print(f"FAIL: {file_b} does not exist")
    exit(1)

data_a = file_a.read_bytes()
data_b = file_b.read_bytes()

if data_a == data_b:
    print("PASS: occamy_xilinx.sv matches the patched golden file")
    exit(0)
else:
    print("FAIL: occamy_xilinx.sv differs from the patched golden file")
    exit(1)
