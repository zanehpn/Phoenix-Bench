## Phase 1: FIX ANALYSIS

### 1) What the problem is
The FPGA build for `occamy_vcu128` fails because `occamy_xilinx.sv` includes a missing header file:

```systemverilog
`include "axi_flat.svh"
```

This file is not present in the repository, so the macros used later in the module are undefined:

- `AXI_FLATTEN_MASTER`
- `AXI_FLATTEN_SLAVE`

As a result, synthesis stops with include/macro errors.

---

### 2) Where the problem occurs
The issue is in:

- `hw/system/occamy/src/occamy_xilinx.sv`

Specifically:

- near the top of the file, where it includes `axi_flat.svh`
- later in the file, where the missing macros are invoked to flatten AXI interface structs into module ports

The provided failing locations are correct:
- the include at the top of the file
- the macro use around the PCIe/HBM AXI port declarations

---

### 3) Best practices to take into account
When fixing this kind of issue:

- **Prefer minimal changes**: only modify what is necessary to restore buildability.
- **Preserve generated code structure**: the file is marked as automatically generated, so avoid large manual edits unless unavoidable.
- **Avoid introducing new dependencies unnecessarily**: if the repository already contains the equivalent functionality elsewhere, reuse it instead of adding a new file.
- **Keep compatibility with existing build flow**: the fix should allow current synthesis scripts to work without requiring extra manual setup.

---

### 4) How to fix the problem
The best fix is to replace the missing include with the correct existing source of the AXI flattening macros, or otherwise make the macros available from a repository-tracked file.

Since the error indicates that `axi_flat.svh` is missing, the simplest and most targeted fix is:

- update `occamy_xilinx.sv` to include the correct macro definition file already present in the repository, if available
- if the repository does not contain an equivalent file, then the missing header must be added

Given the issue context, the intended repair is to restore the missing macro include dependency so the `AXI_FLATTEN_*` macros resolve during synthesis.

---

## Phase 2: FIX IMPLEMENTATION

I can provide the patch, but I need one additional piece of repository context to do it correctly and minimally:

- whether there is an existing replacement file for `axi_flat.svh` elsewhere in the repo
- or the exact contents/path of the intended header if it should be added

Because only the failing file snippets were provided, I cannot safely fabricate the missing header content or point the include to a file path that may not exist.

### What I can patch now
If you want, I can immediately produce a minimal patch for:

- `hw/system/occamy/src/occamy_xilinx.sv`

to change the include to the correct repository path once you confirm where the macro definitions live.

### Example patch shape
```text
<file>hw/system/occamy/src/occamy_xilinx.sv</file>
<original>
`include "axi_flat.svh"
</original>
<patched>
`include "REPLACE_WITH_EXISTING_HEADER_PATH.svh"
</patched>
```

If you share the repo tree or the location of the AXI flatten macros, I can give you the exact final patch in the required format.