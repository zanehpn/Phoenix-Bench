## Phase 1: FIX ANALYSIS

### 1. What the problem is
`axi_lite_mux_intf` is declared with the wrong interface type on its ports.  
It is an AXI4-Lite mux, but its interface ports `slv` and `mst` are typed as `AXI_BUS` instead of `AXI_LITE`.

This causes Verilator elaboration to fail because the instance is connected to `AXI_LITE` interfaces, while the module expects `AXI_BUS`.

### 2. Where the problem occurs
The issue is in `src/axi_lite_mux.sv`, in the interface wrapper module definition for `axi_lite_mux_intf`.

The buggy declaration is:

```systemverilog
AXI_BUS.Slave  slv [NoSlvPorts-1:0],
AXI_BUS.Master mst
```

These should be `AXI_LITE` interface types to match the module’s AXI4-Lite semantics and the rest of the codebase.

### 3. Best practices to take into account
- Make the fix minimal and localized.
- Preserve the existing AXI4-Lite channel logic; only correct the interface typing.
- Ensure the interface wrapper matches the internal `axi_lite_mux` implementation and the corresponding `AXI_LITE` assignment macros.
- Avoid changing unrelated modules or other AXI full-feature components.

### 4. How to fix the problem
Change the interface port types in `axi_lite_mux_intf` from `AXI_BUS` to `AXI_LITE` for both:
- `slv`
- `mst`

This aligns the wrapper with the AXI4-Lite mux implementation and resolves the Verilator type mismatch.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/axi_lite_mux.sv</file>
<original>
module axi_lite_mux_intf #(
  parameter int unsigned NoSlvPorts = 1,
  parameter int unsigned NoMstPorts = 1,
  parameter int unsigned AddrWidth  = 32,
  parameter int unsigned DataWidth  = 32
) (
  input  logic                   clk_i,    // Clock
  input  logic                   rst_ni,   // Asynchronous reset active low
  input  logic                   test_i,   // Test Mode enable
  AXI_BUS.Slave                  slv [NoSlvPorts-1:0], // slave ports
  AXI_BUS.Master                 mst                   // master port
);
</original>
<patched>
module axi_lite_mux_intf #(
  parameter int unsigned NoSlvPorts = 1,
  parameter int unsigned NoMstPorts = 1,
  parameter int unsigned AddrWidth  = 32,
  parameter int unsigned DataWidth   = 32
) (
  input  logic                   clk_i,    // Clock
  input  logic                   rst_ni,   // Asynchronous reset active low
  input  logic                   test_i,   // Test Mode enable
  AXI_LITE.Slave                 slv [NoSlvPorts-1:0], // slave ports
  AXI_LITE.Master                mst                   // master port
);
</patched>
```