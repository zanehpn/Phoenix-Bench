### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue reports two observable anomalies during `WFI` + interrupt activity:

- A warning about reading uninitialized RAM while reading `GPIO_OUTPUT_VAL` (which should be initialized/previously written).
- `mip.MTIP` transitions appearing at surprising points relative to instruction trace and `WFI`.

These are consistent with:
- **Uninitialized peripheral read-data register** (`Dout`) in GPIO APB.
- **Tracer CSR sampling gated by `valid` instead of pipeline stall state**, which can delay or mis-time visibility of asynchronous CSR changes (like interrupt-pending bits) around `WFI`.

2. **Where the problems are in code**

- `src/uncore/gpio_apb.sv`:
  - `Dout` is used to drive `PRDATA` but is **not reset** in the reset block.
- `testbench/common/wallyTracer.sv`:
  - `CONNECT_CSR` macro currently uses:
    - `assign rvvi.csr[...] = valid ? val : prev...`
  - This freezes CSR observation whenever `valid=0` (e.g. during bubbles / `WFI` idle), even though comment intent is to hold during **writeback stall**, not lack of retired instruction.

3. **Best practices for fix**

- Ensure externally visible read-data paths are initialized on reset.
- For trace coherence, gate sampled architectural state using **pipeline stall/flow control**, not retirement-valid alone, when capturing asynchronous state changes.
- Keep patch minimal and localized to avoid changing architectural behavior.

4. **Fix approach**

- In `gpio_apb.sv`, reset `Dout` to zero.
- In `wallyTracer.sv`, update `CONNECT_CSR` to hold CSR value on `StallW` (as intended), not on `valid`.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>testbench/common/wallyTracer.sv</file>
<original>// Since we are detecting the CSR change by comparing the old value, we need to
// ensure the CSR is detected when the pipeline's Writeback stage is not
// stalled.  If it is stalled we want to hold the old value.
`define CONNECT_CSR(name, addr, val) \
  logic [P.XLEN-1:0] prev_csr_``name; \
  always_ff @(posedge clk) \
    prev_csr_``name <= rvvi.csr[0][0][addr]; \
  assign rvvi.csr_wb[0][0][addr] = (rvvi.csr[0][0][addr] != prev_csr_``name); \
  assign rvvi.csr[0][0][addr] = valid ? val : prev_csr_``name;</original>
<patched>// Since we are detecting the CSR change by comparing the old value, we need to
// ensure the CSR is detected when the pipeline's Writeback stage is not
// stalled.  If it is stalled we want to hold the old value.
`define CONNECT_CSR(name, addr, val) \
  logic [P.XLEN-1:0] prev_csr_``name; \
  always_ff @(posedge clk) \
    prev_csr_``name <= rvvi.csr[0][0][addr]; \
  assign rvvi.csr_wb[0][0][addr] = (rvvi.csr[0][0][addr] != prev_csr_``name); \
  assign rvvi.csr[0][0][addr] = ~StallW ? val : prev_csr_``name;</patched>
```

# modification 2
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