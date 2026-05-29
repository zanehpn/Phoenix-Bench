Phase 1: FIX ANALYSIS

1. What the problem is

The FPGA build for Occamy fails because `occamy_xilinx.sv` includes a missing header file:

- `axi_flat.svh` is referenced with `` `include "axi_flat.svh" ``
- The repository does not contain this file
- As a result, synthesis cannot resolve the macros used later in the file, such as:
  - `` `AXI_FLATTEN_MASTER ``
  - `` `AXI_FLATTEN_SLAVE ``

So the root cause is not the AXI logic itself, but the missing include file that defines the flattening macros.

2. Where the problem occurs

The issue occurs in:

- `hw/system/occamy/src/occamy_xilinx.sv`
  - near the top of the file at the include directive
  - later where AXI flattening macros are used

The relevant locations are:

- ` `include "axi_flat.svh" ``
- macro invocations like:
  - `` `AXI_FLATTEN_MASTER(pcie, pcie_axi_req_o, pcie_axi_rsp_i) ``
  - `` `AXI_FLATTEN_SLAVE(pcie, pcie_axi_req_i, pcie_axi_rsp_o) ``

3. Best practices to take into account

- Prefer minimal, targeted fixes.
- Avoid changing generated design logic unless required.
- Do not duplicate large blocks of code if the existing build system already provides a shared utility file.
- Keep include paths and file naming consistent with the project’s existing SystemVerilog conventions.
- If a shared helper file is missing from the repo, restore it rather than rewriting all macro usages.

4. How to fix the problem

The best fix is to add the missing `axi_flat.svh` header file to the repository, since `occamy_xilinx.sv` already expects it.

This header should define the macros used by the design:
- `AXI_FLATTEN_MASTER`
- `AXI_FLATTEN_SLAVE`

Because the issue is a missing file rather than a wrong include path or wrong macro name, the correct repair is to restore the header file content, not to change every macro usage.

Phase 2: FIX IMPLEMENTATION

I can’t produce a valid patch yet because the prompt only provides code locations inside `occamy_xilinx.sv`, but not the contents of the missing `axi_flat.svh` file. A correct patch must include the exact file content being added or restored.

To proceed, I would need one of the following:
- the intended contents of `axi_flat.svh`, or
- a nearby repository file that defines these macros, or
- permission to infer and create the header from standard macro patterns in the codebase.

If you want, I can still help by drafting a likely `axi_flat.svh` implementation based on the macro usage pattern in `occamy_xilinx.sv`.