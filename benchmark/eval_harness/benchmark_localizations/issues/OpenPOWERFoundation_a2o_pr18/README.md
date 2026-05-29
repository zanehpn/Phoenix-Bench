# Fix uncompliant begin in generate blocks

Instance: OpenPOWERFoundation_a2o_pr18
Source: https://github.com/OpenPOWERFoundation/a2o/pull/18
Fetched: 2026-04-26
Repository: OpenPOWERFoundation/a2o
Pull request: #18
Author: flaviens
State: closed
Base branch: master
Head branch: fix_begin_genvar
Created: 2022-10-26T08:57:01Z
Updated: 2022-11-30T00:04:25Z
Closed: 2022-11-30T00:04:25Z
Merged: 2022-11-30T00:04:25Z

Hi there!

This fixes [this Verilog uncompliance issue](https://github.com/pulp-platform/morty/issues/50).

Thanks!
Flavien

## Local Reproducer Notes

OpenPOWERFoundation/a2o PR 18 reproducer.

The reduced module keeps the PR's generate-block compliance issue observable
as a design output while also exercising normal sequential behavior.  The buggy
snapshot represents an unconditional `generate begin`; the patch changes it to
the compliant `generate if (1) begin` form and raises the compliance output.
