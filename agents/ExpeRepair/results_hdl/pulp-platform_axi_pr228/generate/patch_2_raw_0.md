Phase 1: FIX ANALYSIS

1. Problem summary  
`axi_lite_mux_intf` is declared with the wrong interface types for its ports. It currently uses `AXI_BUS.Slave` / `AXI_BUS.Master`, but this module is the AXI4-Lite wrapper and should use `AXI_LITE.Slave` / `AXI_LITE.Master`. Verilator then fails elaboration because the connected interface instance has type `AXI_LITE`, not `AXI_BUS`.

2. Where the problem occurs  
The issue is in `src/axi_lite_mux.sv`, in the `axi_lite_mux_intf` module declaration. The port list incorrectly declares:
- `AXI_BUS.Slave slv [NoSlvPorts-1:0]`
- `AXI_BUS.Master mst`

This is inconsistent with:
- the module name and comments describing AXI4-Lite behavior
- the internal non-intf implementation, which operates on AXI4-Lite request/response types
- the rest of the xbar code, which instantiates `axi_lite_mux_intf` with `AXI_LITE` interfaces

3. Best practices to apply  
- Keep interface types consistent with module semantics and wrapper layer.
- Make the smallest possible fix that corrects the type mismatch.
- Avoid changing the underlying mux logic unless necessary; the bug is in the interface wrapper declarations.
- Ensure the interface wrapper matches the existing assignment macros and AXI4-Lite typedefs already used elsewhere in the file.

4. How to fix it  
Change the `axi_lite_mux_intf` port declarations from `AXI_BUS` to `AXI_LITE`:
- `AXI_BUS.Slave` → `AXI_LITE.Slave`
- `AXI_BUS.Master` → `AXI_LITE.Master`

This is sufficient to resolve the Verilator elaboration error.

Phase 2: FIX IMPLEMENTATION

```text
<file>src/axi_lite_mux.sv</file>
<original>
module axi_lite_mux_intf #(
  parameter int unsigned NoSlvPorts = 0,
  parameter int unsigned MaxTrans   = 0,
  parameter bit          FallThrough = 1'b0,
  parameter bit          SpillAw     = 1'b1,
  parameter bit          SpillW      = 1'b0,
  parameter bit          SpillB      = 1'b0,
  parameter bit          SpillAr     = 1'b1,
  parameter bit          SpillR      = 1'b0
) (
  input  logic   clk_i,                // Clock
  input  logic   rst_ni,               // Asynchronous reset active low
  input  logic   test_i,               // Testmode enable
  AXI_BUS.Slave  slv [NoSlvPorts-1:0], // slave ports
  AXI_BUS.Master mst                   // master port
);
</original>
<patched>
module axi_lite_mux_intf #(
  parameter int unsigned NoSlvPorts = 0,
  parameter int unsigned MaxTrans   = 0,
  parameter bit          FallThrough = 1'b0,
  parameter bit          SpillAw     = 1'b1,
  parameter bit          SpillW      = 1'b0,
  parameter bit          SpillB      = 1'b0,
  parameter bit          SpillAr     = 1'b1,
  parameter bit          SpillR      = 1'b0
) (
  input  logic    clk_i,                // Clock
  input  logic    rst_ni,               // Asynchronous reset active low
  input  logic    test_i,               // Testmode enable
  AXI_LITE.Slave  slv [NoSlvPorts-1:0], // slave ports
  AXI_LITE.Master mst                   // master port
);
</patched>
```