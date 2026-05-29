## Phase 1: FIX ANALYSIS

### 1) What the problem is
The FPGA build of Occamy fails because `occamy_xilinx.sv` includes a missing header:

- `axi_flat.svh` is not present in the repository
- therefore the macros `AXI_FLATTEN_MASTER` and `AXI_FLATTEN_SLAVE` are undefined
- synthesis stops with include/macro errors

This is not a logic bug in the design itself; it is a missing dependency in the repo.

### 2) Where the problem occurs
The issue is in `hw/system/occamy/src/occamy_xilinx.sv`:

- at the top of the file:
  - `` `include "axi_flat.svh" ``
- later in the module body:
  - use of `` `AXI_FLATTEN_MASTER(...) ``
  - use of `` `AXI_FLATTEN_SLAVE(...) ``

Since the included file is absent, these macros cannot be expanded.

### 3) Best practices to take into account
- Prefer minimal fixes: only change what is required to restore buildability.
- Avoid introducing new behavior changes in generated RTL unless necessary.
- Do not break existing synthesis/flow assumptions.
- If a missing include is referenced, either:
  - restore the missing file, or
  - remove the dependency by inlining equivalent macro functionality.

Because the issue is specifically a missing repo file and the generated RTL depends on the macros, the cleanest fix is to add the missing include file with the expected macro definitions.

### 4) How to fix the problem
Add `axi_flat.svh` to the repo at the location expected by the include path, implementing the `AXI_FLATTEN_MASTER` and `AXI_FLATTEN_SLAVE` macros used by `occamy_xilinx.sv`.

This resolves:
- the missing include error
- the undefined macro error

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>hw/system/occamy/src/axi_flat.svh</file>
<original></original>
<patched>`ifndef AXI_FLAT_SVH
`define AXI_FLAT_SVH

`include "axi/assign.svh"

// Flatten a master AXI interface struct into ports and connect signals
`define AXI_FLATTEN_MASTER(NAME, REQ, RSP) \
  `AXI_ASSIGN_TO_REQ(NAME, REQ) \
  `AXI_ASSIGN_FROM_RSP(NAME, RSP)

// Flatten a slave AXI interface struct into ports and connect signals
`define AXI_FLATTEN_SLAVE(NAME, REQ, RSP) \
  `AXI_ASSIGN_TO_REQ(NAME, REQ) \
  `AXI_ASSIGN_FROM_RSP(NAME, RSP)

`endif
</patched>
```