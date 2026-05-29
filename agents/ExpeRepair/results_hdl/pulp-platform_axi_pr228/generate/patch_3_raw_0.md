### Phase 1: FIX ANALYSIS

#### 1) What the problem is
`axi_lite_mux_intf` is declared with the wrong interface type for its ports.  
It uses `AXI_BUS.Slave` and `AXI_BUS.Master`, but this module is an AXI4-Lite mux and should use `AXI_LITE.Slave` and `AXI_LITE.Master`.

This causes Verilator elaboration to fail because the connected interface instance is `AXI_LITE`, not `AXI_BUS`.

#### 2) Where the problem occurs
The issue is in `src/axi_lite_mux.sv`, in the interface wrapper module `axi_lite_mux_intf`.

The problematic port declaration is:
```systemverilog
AXI_BUS.Slave  slv [NoSlvPorts-1:0],
AXI_BUS.Master mst
```

This mismatch is exactly what Verilator reports when connecting `.mst (axi_sauria)`.

#### 3) Best practices to take into account
- Make the fix minimal and localized.
- Keep the wrapper consistent with the underlying module and the rest of the AXI4-Lite codebase.
- Do not change unrelated logic or signal wiring.
- Use the correct interface type matching the module’s semantics: AXI4-Lite, not full AXI.

#### 4) How to fix it
Change the port interface types in `axi_lite_mux_intf` from `AXI_BUS` to `AXI_LITE` for both slave and master ports.

No other logic changes are necessary.

---

### Phase 2: FIX IMPLEMENTATION

```text
<file>src/axi_lite_mux.sv</file>
<original>
module axi_lite_mux_intf #(
  parameter int unsigned NoSlvPorts = 32'd0,
  parameter int unsigned MaxTrans   = 32'd0,
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
  parameter int unsigned NoSlvPorts = 32'd0,
  parameter int unsigned MaxTrans   = 32'd0,
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