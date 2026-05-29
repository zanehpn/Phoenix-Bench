## Phase 1: FIX ANALYSIS

### 1) What the problem is
The FPGA build for Occamy fails because `occamy_xilinx.sv` includes a missing header file:

```systemverilog
`include "axi_flat.svh"
```

Vivado reports:
- it cannot open `axi_flat.svh`
- therefore the macros `AXI_FLATTEN_MASTER` and `AXI_FLATTEN_SLAVE` are undefined

This means the build depends on a file that is not present in the repository, so synthesis cannot proceed.

---

### 2) Where the problem occurs
The issue occurs in `hw/system/occamy/src/occamy_xilinx.sv`:

- At the top of the file, the include is missing from the repo:
  ```systemverilog
  `include "axi_flat.svh"
  ```

- Later in the same file, the missing macros are used:
  ```systemverilog
  `AXI_FLATTEN_MASTER(...)
  `AXI_FLATTEN_SLAVE(...)
  ```

So the root cause is not the macro usage itself, but the missing header file that defines those macros.

---

### 3) Best practices to take into account
- **Minimal change**: only fix the missing dependency; do not alter unrelated logic.
- **Keep synthesis compatibility**: the fix should preserve the current interface and generated structure.
- **Avoid introducing new build assumptions** unless necessary.
- **Do not duplicate macro logic** in the source file if the project already expects a shared helper header.

---

### 4) How to fix the problem
The correct fix is to restore the missing `axi_flat.svh` file in the repository, since `occamy_xilinx.sv` already expects it and uses its macros.

Because the issue description and provided code only expose `occamy_xilinx.sv`, the minimal repository-level resolution is to ensure the include file is present at the expected location and contains the macro definitions for:
- `AXI_FLATTEN_MASTER`
- `AXI_FLATTEN_SLAVE`

No changes are needed to the macro call sites in `occamy_xilinx.sv`.

---

## Phase 2: FIX IMPLEMENTATION

I cannot produce a valid patch from the provided context alone because the missing file `axi_flat.svh` is not included in the available code locations, and the instructions require the patch to modify only code snippets present in the supplied locations with exact continuous `<original>` blocks.

### What should be patched
The repository should add:

- `hw/system/occamy/src/axi_flat.svh`

with the macro definitions expected by `occamy_xilinx.sv`.

However, since that file is not among the provided code locations, I cannot write a conforming `<original>...</original>` / `<patched>...</patched>` patch for it under your strict format constraints.

If you provide the contents of `axi_flat.svh` from the upstream repository or allow a patch that adds a new file without an `<original>` block, I can generate the exact fix immediately.