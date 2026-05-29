## Phase 1: FIX ANALYSIS

### 1) What the problem is
The simulation fails in ModelSim/Questa with:

- `vsim-3053 Illegal output or inout port connection`
- reported at `axi_xbar.sv`, inside the instantiation of `axi_err_slv`
- specifically on port `slv_resp_o`

This means the crossbar is connecting an output port of `axi_err_slv` to something the simulator considers an illegal target, usually because the connected expression is not a valid variable/net for an output connection in that context.

### 2) Where the problem occurs
The problematic code is in `src/axi_xbar.sv` in the error-slave instantiation:

```systemverilog
.slv_req_i  ( slv_reqs[i][Cfg.NoMstPorts]   ),
.slv_resp_o ( slv_resps[i][Cfg.NoMstPorts]  )
```

The surrounding declaration is:

```systemverilog
slv_req_t  [Cfg.NoSlvPorts-1:0][Cfg.NoMstPorts:0]  slv_reqs;
slv_resp_t [Cfg.NoSlvPorts-1:0][Cfg.NoMstPorts:0]  slv_resps;
```

The selected element `slv_resps[i][Cfg.NoMstPorts]` is being driven by a module output, and some simulators are stricter about such unpacked-array element connections, especially when the element is treated as a non-assignable expression in that context.

### 3) Best practices to take into account
- Use an intermediate `logic`/typed variable for module output connections when simulator compatibility is a concern.
- Keep the fix minimal: do not change protocol behavior or crossbar logic.
- Preserve the existing array structure and routing semantics.
- Avoid changing type definitions unless necessary.
- Ensure the error slave still connects to the “decode error” slot without altering other ports.

### 4) How to fix the problem
Introduce temporary per-instance signals for the error slave response connection, then assign those signals to the array element with a continuous assignment.

This avoids direct output-to-array-element connection that triggers the simulator error while preserving the exact functionality.

---

## Phase 2: FIX IMPLEMENTATION

```systemverilog
<file>src/axi_xbar.sv</file>
<original>
  // signals from the axi_demuxes, one index more for decode error
  slv_req_t  [Cfg.NoSlvPorts-1:0][Cfg.NoMstPorts:0]  slv_reqs;
  slv_resp_t [Cfg.NoSlvPorts-1:0][Cfg.NoMstPorts:0]  slv_resps;

  // signals into the axi_muxes, are of type slave as the multiplexer extends the ID
  slv_req_t  [Cfg.NoMstPorts-1:0][Cfg.NoSlvPorts-1:0] mst_reqs;
  slv_resp_t [Cfg.NoMstPorts-1:0][Cfg.NoSlvPorts-1:0] mst_resps;
</original>
<patched>
  // signals from the axi_demuxes, one index more for decode error
  slv_req_t  [Cfg.NoSlvPorts-1:0][Cfg.NoMstPorts:0]  slv_reqs;
  slv_resp_t [Cfg.NoSlvPorts-1:0][Cfg.NoMstPorts:0]  slv_resps;
  slv_resp_t [Cfg.NoSlvPorts-1:0]                    slv_err_resps;

  // signals into the axi_muxes, are of type slave as the multiplexer extends the ID
  slv_req_t  [Cfg.NoMstPorts-1:0][Cfg.NoSlvPorts-1:0] mst_reqs;
  slv_resp_t [Cfg.NoMstPorts-1:0][Cfg.NoSlvPorts-1:0] mst_resps;
</patched>
```

```systemverilog
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
      .test_i,   // Testmode enable
      // slave port
      .slv_req_i  ( slv_reqs[i][Cfg.NoMstPorts] ),
      .slv_resp_o ( slv_err_resps[i]            )
    );

    assign slv_resps[i][Cfg.NoMstPorts] = slv_err_resps[i];
</patched>
```