### Phase 1: FIX ANALYSIS

#### 1. What the problem is
`axi_lite_mux_intf` is declared with the wrong interface types for its ports.  
It is meant to be an AXI4-Lite mux, but the interface wrapper declares:

- `AXI_BUS.Slave slv [...]`
- `AXI_BUS.Master mst`

instead of using the AXI-Lite interface type.

This causes Verilator elaboration to fail because the instantiated module expects `AXI_BUS` while the connections are `AXI_LITE`.

#### 2. Where the problem occurs
The issue is in the interface wrapper for the AXI-Lite mux, in `src/axi_lite_mux.sv`, around the `axi_lite_mux_intf` module declaration.

The problematic part is the interface port list:
- `AXI_BUS.Slave  slv ...`
- `AXI_BUS.Master mst ...`

Since the module is AXI-Lite-specific, these should be `AXI_LITE` interfaces.

#### 3. Best practices to take into account
- Make the smallest possible change that fixes the mismatch.
- Preserve the existing AXI-Lite datapath and internal logic.
- Avoid modifying unrelated modules or conversion logic.
- Keep the interface wrapper consistent with the underlying module’s protocol and typedefs.

#### 4. How to fix the problem
Change the interface declaration of `axi_lite_mux_intf` so that both ports use `AXI_LITE` instead of `AXI_BUS`:

- `AXI_LITE.Slave slv [...]`
- `AXI_LITE.Master mst`

No other functional changes are needed.

---

### Phase 2: FIX IMPLEMENTATION

```xml
<file>src/axi_lite_mux.sv</file>
<original>
module axi_lite_mux_intf #(
  parameter axi_pkg::xbar_cfg_t Cfg = '0,
  parameter type rule_t             = axi_pkg::xbar_rule_64_t
) (
  input  logic                                                    clk_i,
  input  logic                                                    rst_ni,
  input  logic                                                    test_i,
  AXI_BUS.Slave                                                   slv [Cfg.NoSlvPorts-1:0],
  AXI_BUS.Master                                                  mst
);
</original>
<patched>
module axi_lite_mux_intf #(
  parameter axi_pkg::xbar_cfg_t Cfg = '0,
  parameter type rule_t             = axi_pkg::xbar_rule_64_t
) (
  input  logic                                                    clk_i,
  input  logic                                                    rst_ni,
  input  logic                                                    test_i,
  AXI_LITE.Slave                                                  slv [Cfg.NoSlvPorts-1:0],
  AXI_LITE.Master                                                 mst
);
</patched>
```

