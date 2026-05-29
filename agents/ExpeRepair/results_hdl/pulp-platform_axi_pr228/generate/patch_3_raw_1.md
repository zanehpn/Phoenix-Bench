## Phase 1: FIX ANALYSIS

### 1) What the problem is
`axi_lite_mux_intf` is declared with `AXI_BUS.Slave` / `AXI_BUS.Master` interface ports, but it is intended to be the AXI4-Lite interface variant. Verilator therefore reports a type mismatch when an `AXI_LITE` interface is connected to a port expecting `AXI_BUS`.

In short: **the interface type in `axi_lite_mux_intf` is wrong**.

### 2) Where the problem occurs
The issue is in `src/axi_lite_mux.sv`, in the interface wrapper module definition of `axi_lite_mux_intf`.

The problematic port declarations are:

- `AXI_BUS.Slave  slv [NoSlvPorts-1:0]`
- `AXI_BUS.Master mst`

These should correspond to the AXI-Lite interface types used throughout the rest of the file and by the surrounding AXI-Lite crossbar logic.

### 3) Best practices to take into account
- **Make the smallest possible change**: only fix the interface type mismatch.
- **Preserve consistency** with the surrounding module, which already uses AXI-Lite-specific typedefs/macros.
- **Avoid changing internal logic** unless necessary; the bug is in the interface wrapper declaration, not the mux implementation.
- **Keep naming and API stable** except for correcting the type annotations.

### 4) How to fix the problem
Change the wrapper module ports in `axi_lite_mux_intf` from `AXI_BUS` to `AXI_LITE`:

- `AXI_BUS.Slave` → `AXI_LITE.Slave`
- `AXI_BUS.Master` → `AXI_LITE.Master`

This aligns the wrapper with the rest of the AXI4-Lite implementation and resolves the elaboration/type mismatch.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/axi_lite_mux.sv</file>
<original>
module axi_lite_mux_intf #(
  parameter int unsigned NoSlvPorts = 1
) (
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   test_i,
  AXI_BUS.Slave  slv [NoSlvPorts-1:0],
  AXI_BUS.Master mst
);
</original>
<patched>
module axi_lite_mux_intf #(
  parameter int unsigned NoSlvPorts = 1
) (
  input  logic                    clk_i,
  input  logic                    rst_ni,
  input  logic                    test_i,
  AXI_LITE.Slave  slv [NoSlvPorts-1:0],
  AXI_LITE.Master mst
);
</patched>
```

