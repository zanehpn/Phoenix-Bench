### Phase 1: FIX ANALYSIS

#### 1) What the problem is
`axi_lite_mux_intf` is declared with interface ports of type `AXI_BUS`, but the module is an AXI4-Lite mux and is instantiated with `AXI_LITE` interfaces. Verilator therefore rejects the elaboration because the interface types do not match.

#### 2) Where the problem occurs
The issue is in `src/axi_lite_mux.sv`, in the interface-based wrapper module `axi_lite_mux_intf`.

The problematic port declaration is:

- `AXI_BUS.Slave slv [NoSlvPorts-1:0]`
- `AXI_BUS.Master mst`

These should be AXI-Lite interface types instead.

#### 3) Best practices to consider
- Make the interface wrapper type-consistent with the underlying logic-based module `axi_lite_mux`, which is clearly AXI4-Lite only.
- Keep the fix minimal and local to the incorrect interface declarations.
- Avoid changing the non-interface core mux implementation, since it already appears correct and is used by the wrapper.
- Preserve the existing naming and structure, only correcting the interface types.

#### 4) How to fix it
Change the interface port types in `axi_lite_mux_intf` from `AXI_BUS` to `AXI_LITE` for both slave and master ports.

This aligns the wrapper with the rest of the AXI-Lite design and resolves the Verilator elaboration error.

---

### Phase 2: FIX IMPLEMENTATION

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
  parameter int unsigned MaxTrans    = 32'd0,
  parameter bit          FallThrough = 1'b0,
  parameter bit          SpillAw     = 1'b1,
  parameter bit          SpillW      = 1'b0,
  parameter bit          SpillB      = 1'b0,
  parameter bit          SpillAr     = 1'b1,
  parameter bit          SpillR      = 1'b0
) (
  input  logic   clk_i,
  input  logic   rst_ni,
  input  logic   test_i,
  AXI_BUS.Slave  slv [NoSlvPorts-1:0],
  AXI_BUS.Master mst
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
  parameter int unsigned MaxTrans    = 32'd0,
  parameter bit          FallThrough = 1'b0,
  parameter bit          SpillAw     = 1'b1,
  parameter bit          SpillW      = 1'b0,
  parameter bit          SpillB      = 1'b0,
  parameter bit          SpillAr     = 1'b1,
  parameter bit          SpillR      = 1'b0
) (
  input  logic    clk_i,
  input  logic    rst_ni,
  input  logic    test_i,
  AXI_LITE.Slave  slv [NoSlvPorts-1:0],
  AXI_LITE.Master mst
);
</patched>
```

