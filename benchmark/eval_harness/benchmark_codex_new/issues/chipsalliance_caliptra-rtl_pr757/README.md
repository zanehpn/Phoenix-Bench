# [RTL] AXI Sub Arb fix. Add recovery inf synchros. Export trace signals. Move SS dbg unlock reg to pwrgood.

Instance: chipsalliance_caliptra-rtl_pr757
Source: https://github.com/chipsalliance/caliptra-rtl/pull/757
Fetched: 2026-04-26
Repository: chipsalliance/caliptra-rtl
Pull request: #757
Author: calebofearth
State: closed
Base branch: msft-daily-20250226
Head branch: cwhitehead-msft-axi-sub-fix
Created: 2025-02-26T06:10:12Z
Updated: 2025-02-27T07:10:02Z
Closed: 2025-02-27T07:09:58Z
Merged: 2025-02-27T07:09:58Z

AXI Sub Arb fix. 
* Resolves #753 

Add synchronizers to input signals from subsystem recovery interface. 
Export RISC-V trace signals for debug.
Move SS dbg unlock level reg to pwrgood so it's sticky and persists across warm resets without having to redo the debug unlock flow.

## Local Reproducer Notes

# chipsalliance_caliptra-rtl_pr757

Minimal fail-to-pass Verilator case for the AXI subordinate arbiter priority fix.

The buggy arbiter does not keep write priority while a held final write beat is still in progress, allowing a later read to steal the component interface. The patch keeps priority for any in-progress transfer.
