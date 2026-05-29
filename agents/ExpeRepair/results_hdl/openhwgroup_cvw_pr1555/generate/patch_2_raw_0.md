### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue reports tracer anomalies around `wfi` + interrupt behavior:

- False “read from uninitialized RAM” warning appears around a GPIO MMIO read.
- `mip.MTIP` transitions are reported at surprising instruction points (appearing delayed/misaligned relative to `wfi`/timer activity).

This strongly suggests **trace timing/alignment**, not core functional logic.

2. **Where problem occurs**

In `testbench/common/wallyTracer.sv`, the CSR connection macro:

```systemverilog
`define CONNECT_CSR(name, addr, val) \
  logic [P.XLEN-1:0] prev_csr_``name; \
  always_ff @(posedge clk) \
    prev_csr_``name <= rvvi.csr[0][0][addr]; \
  assign rvvi.csr_wb[0][0][addr] = (rvvi.csr[0][0][addr] != prev_csr_``name); \
  assign rvvi.csr[0][0][addr] = valid ? val : prev_csr_``name;
```

The macro currently gates CSR updates with `valid`, which suppresses CSR state evolution in cycles without retirement (including WFI-induced pauses/bubbles). This can delay CSR change visibility (like `mip.MTIP`) until a later unrelated instruction, producing the observed anomalies.

3. **Best practices for fix**

- Align tracer-visible architectural state with **pipeline stall semantics**, not strictly instruction retirement.
- Hold previous trace value only when WB is actually stalled.
- Keep changes minimal and local to tracer infrastructure.

4. **How to fix**

Update `CONNECT_CSR` to:
- Track previous CSR value only when `~StallW`.
- Report `csr_wb` changes only when `~StallW`.
- Drive current CSR value from `val` when `~StallW`, otherwise hold previous.

This preserves intended stall handling while preventing misleading delay from `valid` gating.

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
  always_ff @(posedge clk) begin \
    if (reset) prev_csr_``name <= '0; \
    else if (~StallW) prev_csr_``name <= val; \
  end \
  assign rvvi.csr_wb[0][0][addr] = ~StallW & (val != prev_csr_``name); \
  assign rvvi.csr[0][0][addr] = ~StallW ? val : prev_csr_``name;</patched>
```