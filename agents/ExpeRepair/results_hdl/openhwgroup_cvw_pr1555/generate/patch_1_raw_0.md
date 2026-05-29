### Phase 1: FIX ANALYSIS

1. **Problem summary**

From the trace and code context, there are two likely root causes behind the reported anomalies:

- **False “uninitialized RAM” warning on GPIO read**:  
  The GPIO APB peripheral’s read data flop (`Dout`) is not initialized on reset. Early reads can therefore return `X` transiently, which the tracer/memory checker interprets as uninitialized data.

- **`mip.MTIP` transition appears mis-timed in tracer around WFI**:  
  In `wallyTracer`, CSR export via `CONNECT_CSR` is gated by `valid` (retired instruction). This is generally correct for instruction-retire semantics, but **MIP is asynchronous** (interrupt-pending status), so gating it can make MTIP edges appear later/oddly correlated with nearby instructions, especially around WFI.

2. **Where in code**

- `src/uncore/gpio_apb.sv`: reset block initializes many registers but **not `Dout`**.
- `testbench/common/wallyTracer.sv`: `CONNECT_CSR` is used for `MIP` (`12'h344`), which applies retire-time gating to an asynchronous status CSR.

3. **Best practices for the fix**

- Initialize all externally-observable stateful outputs/flops on reset (especially bus read-data flops).
- For asynchronous interrupt-pending visibility in tracing, avoid retire-only gating for status that can change outside instruction retirement.
- Keep changes minimal and targeted to avoid disrupting broader RVVI behavior.

4. **How to fix**

- **GPIO**: add `Dout <= '0;` in reset logic.
- **Tracer**: replace macro-based MIP connection with a custom always-visible MIP mapping (ungated by `valid`) while preserving change detection.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/uncore/gpio_apb.sv</file>
<original>  always_ff @(posedge PCLK)
    if (~PRESETn) begin
      input_en  <= '0;
      output_en <= '0;
      output_val <= '0;
      rise_ie    <= '0;
      rise_ip    <= '0;
      fall_ie    <= '0;
      fall_ip    <= '0;
      high_ie    <= '0;
      high_ip    <= '0;
      low_ie     <= '0;
      low_ip     <= '0;
      iof_en     <= '0;
      iof_sel    <= '0;
      out_xor    <= '0;
    end else begin     // writes</original>
<patched>  always_ff @(posedge PCLK)
    if (~PRESETn) begin
      input_en   <= '0;
      output_en  <= '0;
      output_val <= '0;
      rise_ie    <= '0;
      rise_ip    <= '0;
      fall_ie    <= '0;
      fall_ip    <= '0;
      high_ie    <= '0;
      high_ip    <= '0;
      low_ie     <= '0;
      low_ip     <= '0;
      iof_en     <= '0;
      iof_sel    <= '0;
      out_xor    <= '0;
      Dout       <= '0;
    end else begin     // writes</patched>
```

# modification 2
```xml
<file>testbench/common/wallyTracer.sv</file>
<original>    `CONNECT_CSR(MSCRATCH, 12'h340, testbench.dut.core.priv.priv.csr.csrm.MSCRATCH_REGW);
    `CONNECT_CSR(MEPC, 12'h341, testbench.dut.core.priv.priv.csr.csrm.MEPC_REGW);
    `CONNECT_CSR(MCAUSE, 12'h342, testbench.dut.core.priv.priv.csr.csrm.MCAUSE_REGW);
    `CONNECT_CSR(MTVAL, 12'h343, testbench.dut.core.priv.priv.csr.csrm.MTVAL_REGW);
    `CONNECT_CSR(MIP, 12'h344, testbench.dut.core.priv.priv.csr.csrm.MIP_REGW);</original>
<patched>    `CONNECT_CSR(MSCRATCH, 12'h340, testbench.dut.core.priv.priv.csr.csrm.MSCRATCH_REGW);
    `CONNECT_CSR(MEPC, 12'h341, testbench.dut.core.priv.priv.csr.csrm.MEPC_REGW);
    `CONNECT_CSR(MCAUSE, 12'h342, testbench.dut.core.priv.priv.csr.csrm.MCAUSE_REGW);
    `CONNECT_CSR(MTVAL, 12'h343, testbench.dut.core.priv.priv.csr.csrm.MTVAL_REGW);

    // MIP contains asynchronous interrupt-pending state (e.g., MTIP), so expose it
    // directly rather than gating on retire-valid. This avoids delayed/oddly-timed
    // visibility around WFI and stalled retire windows.
    logic [P.XLEN-1:0] prev_csr_MIP;
    always_ff @(posedge clk)
      prev_csr_MIP <= rvvi.csr[0][0][12'h344];
    assign rvvi.csr_wb[0][0][12'h344] = (rvvi.csr[0][0][12'h344] != prev_csr_MIP);
    assign rvvi.csr[0][0][12'h344]    = {{(P.XLEN-12){1'b0}}, testbench.dut.core.priv.priv.csr.csrm.MIP_REGW};</patched>
```