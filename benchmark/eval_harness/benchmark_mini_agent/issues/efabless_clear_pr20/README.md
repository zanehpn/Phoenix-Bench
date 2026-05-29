# Cocotb updates

Instance: efabless_clear_pr20
Source: https://github.com/efabless/clear/pull/20
Fetched: 2026-04-26
Repository: efabless/clear
Pull request: #20
Author: M0stafaRady
State: closed
Base branch: RTL-dev
Head branch: cocotb-dev
Created: 2023-04-05T10:01:26Z
Updated: 2023-04-05T10:01:43Z
Closed: 2023-04-05T10:01:43Z
Merged: 2023-04-05T10:01:43Z

- Develop script to get the hierarchy of the programming chain 
- Add test for counter

## Local Reproducer Notes

efabless/clear PR 20 reproducer.

The reduced RTL keeps the GPIO power-on macro touched by the PR and exposes
the decoded GPIO 3 pull configuration as signals.  The buggy snapshot powers
GPIO 3 up with the management pulldown setting; the patch changes it to the
management pullup setting expected by the cocotb update.
