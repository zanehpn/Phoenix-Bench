### Phase 1: FIX ANALYSIS

#### 1) What the problem is
The simulation fails in ModelSim/Questa with:

- `vsim-3053: Illegal output or inout port connection for port 'slv_resp_o'`

This means a module output port is being connected to something that the simulator considers non-drivable / illegal in that context. In this case, the issue occurs while instantiating `axi_err_slv` inside the AXI crossbar.

#### 2) Where the problem occurs
The error points to `axi_xbar.sv` around the instantiation of `axi_err_slv`:

```systemverilog
.slv_resp_o ( slv_resps[i][Cfg.NoMstPorts] )
```

The signal `slv_resps` is declared as:

```systemverilog
slv_resp_t [Cfg.NoSlvPorts-1:0][Cfg.NoMstPorts:0] slv_resps;
```

Then the code also does crossbar wiring:

```systemverilog
assign slv_resps[i][j] = mst_resps[j][i];
```

This is already suspicious because `slv_resps[i][Cfg.NoMstPorts]` is being driven by the `axi_err_slv` output, and the same array element may be treated in a way ModelSim does not like due to array slicing / packed-unpacked direction semantics.

The issue is in `axi_xbar.sv`, not in `axi_err_slv.sv`.

#### 3) Best practices to take into account
- Keep changes minimal and localized.
- Avoid changing interface behavior unless necessary.
- Be careful with SystemVerilog packed vs. unpacked array semantics when connecting module ports.
- When a simulator complains about port direction legality, use an intermediate signal if direct array element connection is problematic.
- Preserve synthesis-friendly structure.

#### 4) How to fix the problem
The safest fix is to introduce an intermediate wire for the error slave response per slave-port instance, and then assign it into the `slv_resps` array element.

This avoids direct output-port-to-array-element connection issues that some simulators mishandle.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```text
<file>src/axi_xbar.sv</file>
<original>
  for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_slv_port_demux
    logic [$clog2(Cfg.NoMstPorts)-1:0] dec_aw,        dec_ar;
    mst_port_idx_t                     slv_aw_select, slv_ar_select;
    logic                              dec_aw_valid,  dec_aw_error;
    logic                              dec_ar_valid,  dec_ar_error;
</original>
<patched>
  for (genvar i = 0; i < Cfg.NoSlvPorts; i++) begin : gen_slv_port_demux
    logic [$clog2(Cfg.NoMstPorts)-1:0] dec_aw,        dec_ar;
    mst_port_idx_t                     slv_aw_select, slv_ar_select;
    logic                              dec_aw_valid,  dec_aw_error;
    logic                              dec_ar_valid,  dec_ar_error;
    slv_resp_t                         err_slv_resp;
</patched>
```

# modification 2
```text
<file>src/axi_xbar.sv</file>
<original>
    ) i_axi_err_slv (
      .clk_i,   // Clock
      .rst_ni,  // Asynchronous reset active low
      .test_i,  // Testmode enable
      // slave port
      .slv_req_i  ( slv_reqs[i][Cfg.NoMstPorts]   ),
      .slv_resp_o ( slv_resps[i][Cfg.NoMstPorts]  )
    );
</original>
<patched>
    ) i_axi_err_slv (
      .clk_i,   // Clock
      .rst_ni,  // Asynchronous reset active low
      .test_i,  // Testmode enable
      // slave port
      .slv_req_i  ( slv_reqs[i][Cfg.NoMstPorts]   ),
      .slv_resp_o ( err_slv_resp                 )
    );

    assign slv_resps[i][Cfg.NoMstPorts] = err_slv_resp;
</patched>
```

