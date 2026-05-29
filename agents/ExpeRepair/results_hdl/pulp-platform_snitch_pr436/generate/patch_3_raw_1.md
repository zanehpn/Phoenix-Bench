## Phase 1: FIX ANALYSIS

### 1) What the problem is
The FPGA build for Occamy fails because `occamy_xilinx.sv` includes a missing header file:

- `axi_flat.svh` is not present in the repository
- As a result, the macros `AXI_FLATTEN_MASTER` and `AXI_FLATTEN_SLAVE` are undefined
- This causes synthesis to fail during `make occamy_vcu128`

So the issue is not in the AXI logic itself, but in the missing include file that defines the macros used to flatten AXI structs into port lists.

### 2) Where the problem occurs
The problem occurs in `hw/system/occamy/src/occamy_xilinx.sv` at:

- the include directive near the top:
  - `` `include "axi_flat.svh" ``
- the macro usage later in the module:
  - `` `AXI_FLATTEN_MASTER(...) ``
  - `` `AXI_FLATTEN_SLAVE(...) ``

These macros are referenced multiple times, but they depend on the missing header.

### 3) Best practices to take into account
- **Minimal fix**: only add the missing file or correct the include path; avoid unrelated changes.
- **Compatibility**: preserve the existing generated module structure and macro-based AXI flattening approach.
- **Build correctness**: ensure the included file is available at synthesis time and contains the expected macro definitions.
- **Non-invasive patching**: do not rewrite the module unless necessary; the issue is a missing dependency, not broken logic.

### 4) How to fix the problem
The correct fix is to add the missing `axi_flat.svh` header file to the repository in the location expected by `occamy_xilinx.sv`, with definitions for:

- `AXI_FLATTEN_MASTER`
- `AXI_FLATTEN_SLAVE`

Since the issue report indicates the header is missing from the repo, the solution is to restore/provide that file rather than changing the module usage. This keeps the generated code intact and resolves synthesis errors.

---

## Phase 2: FIX IMPLEMENTATION

I can only safely propose a patch if the missing file’s expected contents are known from repository context. From the provided snippets, the only directly visible code change candidate is the include usage, but changing or removing it would not be the right fix because the macros are still needed.

So the correct repository patch is to **add the missing header file** `hw/system/occamy/src/axi_flat.svh` containing the macro definitions. However, because the exact macro implementation is not present in the provided code context, I cannot produce a reliable exact patch block for that file without risking incompatibility with the rest of the design.

If you want, I can still help by drafting a likely `axi_flat.svh` implementation based on the AXI record types used here, but I’d need either:
- the corresponding file from a related repo/version, or
- the definitions of the AXI request/response structs used in Occamy.

