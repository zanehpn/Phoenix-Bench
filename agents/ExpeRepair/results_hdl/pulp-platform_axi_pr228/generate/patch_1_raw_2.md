## Phase 1: FIX ANALYSIS

### 1. What the problem is
`axi_lite_mux_intf` is declared with interface ports of type `AXI_BUS` instead of `AXI_LITE`.  
As a result, Verilator rejects connections where AXI-Lite interfaces are wired into this module, because the port type does not match the actual interface instance type.

### 2. Where the problem occurs
The bug is in `src/axi_lite_mux.sv`, in the interface-based wrapper/module declaration for `axi_lite_mux_intf`.

The problematic port declarations are:
- `AXI_BUS.Slave  slv [NoSlvPorts-1:0]`
- `AXI_BUS.Master mst`

These should be AXI-Lite interface types, not full AXI bus types.

### 3. Best practices to take into account
- Keep the interface type consistent with the module’s functional scope: this module is an AXI4-Lite mux, so its interface ports must use AXI4-Lite interfaces.
- Make the smallest possible change that fixes the type mismatch.
- Avoid changing unrelated logic or internal signal types if the issue is only in the interface wrapper signature.

### 4. How to fix the problem
Update the `axi_lite_mux_intf` module port declarations from `AXI_BUS` to `AXI_LITE` for both slave and master interface ports.

This is sufficient to resolve the elaboration/type mismatch without modifying the internal mux implementation.

---

## Phase 2: FIX IMPLEMENTATION

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
  input  logic     clk_i,                // Clock
  input  logic     rst_ni,               // Asynchronous reset active low
  input  logic     test_i,               // Testmode enable
  AXI_LITE.Slave   slv [NoSlvPorts-1:0], // slave ports
  AXI_LITE.Master  mst                   // master port
);
</patched>
```