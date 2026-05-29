## Phase 1: FIX ANALYSIS

### 1. What the problem is
`axi_lite_mux_intf` is declared with the wrong interface type for its slave and master ports.  
It currently expects `AXI_BUS` interfaces, but this module is an AXI4-Lite multiplexer and should use `AXI_LITE` interfaces.

This causes elaboration failures in Verilator because the connected interfaces are `AXI_LITE`, not `AXI_BUS`.

### 2. Where the problem occurs
The bug is in:

- `src/axi_lite_mux.sv`

Specifically, in the `axi_lite_mux_intf` module port declaration, where these ports are declared incorrectly:
- `AXI_BUS.Slave slv [NoSlvPorts-1:0]`
- `AXI_BUS.Master mst`

The rest of the file is already implemented in AXI4-Lite terms and does not need changing.

### 3. Best practices to take into account
- Make the fix minimal and local to the incorrect interface declaration.
- Keep the module consistent with its name, documentation, and internal AXI4-Lite types/macros.
- Avoid changing unrelated AXI4/AXI4-Lite conversion logic elsewhere in the file.
- Preserve existing module behavior and type definitions.

### 4. How to fix the problem
Change the interface port types in `axi_lite_mux_intf` from `AXI_BUS` to `AXI_LITE`:
- `AXI_BUS.Slave` → `AXI_LITE.Slave`
- `AXI_BUS.Master` → `AXI_LITE.Master`

No other code changes are necessary.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/axi_lite_mux.sv</file>
<original>
(
  input  logic   clk_i,                // Clock
  input  logic   rst_ni,               // Asynchronous reset active low
  input  logic   test_i,               // Testmode enable
  AXI_BUS.Slave  slv [NoSlvPorts-1:0], // slave ports
  AXI_BUS.Master mst                   // master port
);
</original>
<patched>
(
  input  logic    clk_i,                // Clock
  input  logic    rst_ni,               // Asynchronous reset active low
  input  logic    test_i,               // Testmode enable
  AXI_LITE.Slave  slv [NoSlvPorts-1:0], // slave ports
  AXI_LITE.Master mst                   // master port
);
</patched>
```