## Phase 1: FIX ANALYSIS

### 1) What the problem is
The FPGA build of Occamy fails because `occamy_xilinx.sv` includes a missing SystemVerilog header:

```sv
`include "axi_flat.svh"
```

That header defines the macros:

- `AXI_FLATTEN_MASTER`
- `AXI_FLATTEN_SLAVE`

Without it, synthesis fails with:
- cannot open include file `axi_flat.svh`
- undefined macro `AXI_FLATTEN_MASTER`

So the issue is not with the macro usage itself, but with the missing include file in the repository.

### 2) Where the problem occurs
The problem occurs in:

- `hw/system/occamy/src/occamy_xilinx.sv`
  - at the top of the file where the missing include is referenced
  - later where the macros are invoked for PCIe/HBM port flattening

The provided error points specifically to:
- the include statement near the beginning of the file
- the macro invocations around the AXI port flattening section

### 3) Best practices to take into account
- **Minimal change**: only add what is necessary to restore the build.
- **Preserve generated code**: `occamy_xilinx.sv` is marked as automatically generated, so avoid manually rewriting its logic unless absolutely necessary.
- **Fix the root cause**: the missing header should be restored, not the macro calls removed.
- **Keep compatibility**: the fix should preserve the expected AXI flattening behavior for FPGA synthesis.

### 4) How to fix the problem
Add the missing `axi_flat.svh` header file to the repository at the location expected by the include path, or ensure it is restored as part of the source tree.

Since the provided context only shows `occamy_xilinx.sv`, the most direct and minimal fix is to restore the missing header file content and keep the existing include directive unchanged.

---

## Phase 2: FIX IMPLEMENTATION

I can only produce a valid patch for files and content that are available in the provided context. However, the missing file `axi_flat.svh` itself is not included among the provided code locations, so I cannot safely reconstruct its exact contents here without risking breaking the build.

### Therefore, the correct fix is:
- restore/add `axi_flat.svh` in the include path used by `occamy_xilinx.sv`

If you can provide the expected contents or the repository path where this header should live, I can generate the exact patch in the required format.