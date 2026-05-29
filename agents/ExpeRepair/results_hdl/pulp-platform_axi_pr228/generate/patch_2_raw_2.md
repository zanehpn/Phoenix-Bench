## Phase 1: FIX ANALYSIS

### 1. What the problem is
`axi_lite_mux_intf` is declared with `AXI_BUS` interface ports, but it is used in an AXI4-Lite design and connected to `AXI_LITE` interfaces. Verilator therefore reports a type mismatch:

- expected: `AXI_BUS`
- connected: `AXI_LITE`

This causes elaboration to fail.

### 2. Where the problem occurs
The issue is in `src/axi_lite_mux.sv`, in the interface-based wrapper module `axi_lite_mux_intf`.

The buggy declarations are:

```systemverilog
AXI_BUS.Slave  slv [NoSlvPorts-1:0],
AXI_BUS.Master mst
```

These should use the AXI-Lite interface type, not the full AXI bus interface.

### 3. Best practices to take into account
- Make the interface type match the functionality of the module.
- Keep the fix minimal: only change the interface wrapper, not the internal mux logic.
- Preserve compatibility with existing AXI-Lite typedef/macros and surrounding code.
- Avoid unnecessary renaming or restructuring unless required.

### 4. How to fix the problem
Change the port declarations in `axi_lite_mux_intf` from `AXI_BUS` to `AXI_LITE`:

- `AXI_BUS.Slave` → `AXI_LITE.Slave`
- `AXI_BUS.Master` → `AXI_LITE.Master`

This aligns the wrapper with the rest of the AXI-Lite implementation and resolves the Verilator type mismatch.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/axi_lite_mux.sv</file>
<original>
module axi_lite_mux_intf #(
  parameter type          aw_chan_t  = logic, // AW LITE Channel Type
  parameter type           w_chan_t  = logic, //  W LITE Channel Type
  parameter type           b_chan_t  = logic, //  B LITE Channel Type
  parameter type          ar_chan_t  = logic, // AR LITE Channel Type
  parameter type           r_chan_t  = logic, //  R LITE Channel Type
  parameter type          axi_req_t  = logic, // AXI4-Lite request type
  parameter type         axi_resp_t  = logic, // AXI4-Lite response type
  parameter int unsigned NoSlvPorts  = 32'd0, // Number of slave ports
  // Maximum number of outstanding transactions per write or read
  parameter int unsigned MaxTrans    = 32'd0,
  // If enabled, this multiplexer is purely combinatorial
  parameter bit          FallThrough = 1'b0,
  // add spill register on write master port, adds a cycle latency on write channels
  parameter bit          SpillAw     = 1'b1,
  parameter bit          SpillW      = 1'b0,
  parameter bit          SpillB      = 1'b0,
  // add spill register on read master port, adds a cycle latency on read channels
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
  parameter type          aw_chan_t  = logic, // AW LITE Channel Type
  parameter type           w_chan_t  = logic, //  W LITE Channel Type
  parameter type           b_chan_t  = logic, //  B LITE Channel Type
  parameter type          ar_chan_t  = logic, // AR LITE Channel Type
  parameter type           r_chan_t  = logic, //  R LITE Channel Type
  parameter type          axi_req_t  = logic, // AXI4-Lite request type
  parameter type         axi_resp_t  = logic, // AXI4-Lite response type
  parameter int unsigned NoSlvPorts  = 32'd0, // Number of slave ports
  // Maximum number of outstanding transactions per write or read
  parameter int unsigned MaxTrans    = 32'd0,
  // If enabled, this multiplexer is purely combinatorial
  parameter bit          FallThrough = 1'b0,
  // add spill register on write master port, adds a cycle latency on write channels
  parameter bit          SpillAw     = 1'b1,
  parameter bit          SpillW      = 1'b0,
  parameter bit          SpillB      = 1'b0,
  // add spill register on read master port, adds a cycle latency on read channels
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