# [dv] Add MHPM Counter number param to SpikeCosim

Instance: lowRISC_ibex_pr1821
Source: https://github.com/lowRISC/ibex/pull/1821
Fetched: 2026-04-26
Repository: lowRISC/ibex
Pull request: #1821
Author: ctopal
State: closed
Base branch: master
Head branch: mhpmcounter_spikecosim
Created: 2022-09-28T16:20:26Z
Updated: 2022-10-11T14:52:49Z
Closed: 2022-10-11T14:52:42Z
Merged: 2022-10-11T14:52:42Z

This commit adds another field in SpikeCosim class so that Spike can hardcode the correct event registers.

Signed-off-by: Canberk Topal <ctopal@lowrisc.org>

Needs: https://github.com/lowRISC/riscv-isa-sim/pull/17

Resolves https://github.com/lowRISC/ibex/issues/1820

## Local Reproducer Notes

# lowRISC_ibex_pr1821

Minimal fail-to-pass Verilator case for passing the MHPM counter count into the Spike cosim checker.

The buggy checker ignores the configured MHPM counter count. The patch forwards it to the observable cosim creation configuration.
