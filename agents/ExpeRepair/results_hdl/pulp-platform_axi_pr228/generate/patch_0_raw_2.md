## Phase 1: FIX ANALYSIS

### 1) What the problem is
`axi_lite_mux_intf` is declared with AXI full interface types (`AXI_BUS`) for its slave and master ports, but the module is meant to handle AXI4-Lite interfaces (`AXI_LITE`).  
Because of that mismatch, Verilator fails elaboration when an `AXI_LITE` interface is connected to a port expecting `AXI_BUS`.

### 2) Where the problem occurs
The issue is in `src/axi_lite_mux.sv`, in the interface-based wrapper/module declaration of `axi_lite_mux_intf`.  
The port declarations use:

- `AXI_BUS.Slave slv [...]`
- `AXI_BUS.Master mst`

but the module internally is an AXI4-Lite mux and should use AXI-Lite interface types.

### 3) Best practices to consider
- Keep interface types consistent with the module’s protocol semantics.
- Minimize changes to the interface wrapper only; the struct-based internal mux implementation already appears correct.
- Avoid touching unrelated modules unless they also contain the same type mismatch.
- Preserve existing parameterization and internal signal conversions.

### 4) How to fix it
Change the port interface types in `axi_lite_mux_intf` from `AXI_BUS` to `AXI_LITE` for both slave and master ports.  
No other functional changes are needed.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/axi_lite_mux.sv</file>
<original>
module axi_lite_mux_intf #(
  parameter int unsigned NoSlvPorts = 1
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
  parameter int unsigned NoSlvPorts = 1
) (
  input  logic    clk_i,                // Clock
  input  logic    rst_ni,               // Asynchronous reset active low
  input  logic    test_i,               // Testmode enable
  AXI_LITE.Slave  slv [NoSlvPorts-1:0], // slave ports
  AXI_LITE.Master mst                   // master port
);
</patched>
```

