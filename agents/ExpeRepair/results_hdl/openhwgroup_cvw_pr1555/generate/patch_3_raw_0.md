### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue reports tracer anomalies around `wfi` + timer interrupt behavior:

- Spurious-looking RAM uninitialized warning around MMIO load.
- `mip.MTIP` appears to rise/fall at confusing instruction points, especially around `wfi`.

The strongest tracer-side bug is that CSR sampling in `wallyTracer` is incorrectly gated by `valid` (retirement), which suppresses/defers CSR updates when no instruction retires (exactly what happens during/around `wfi` stalls).

2. **Where the problem occurs**

In `testbench/common/wallyTracer.sv`:

- `CONNECT_CSR` macro currently does:
  - `rvvi.csr[...] = valid ? val : prev`
- This means asynchronous CSR changes (like `mip.MTIP`) are hidden until a later retiring instruction.
- This explains delayed/misaligned interrupt-bit reporting around `wfi`.

Also, `wfiM` is captured but not used in tracer halt signaling (`HaltM` only uses `DCacheFlushStart`), which can further reduce observability of `wfi` hold behavior.

3. **Best practices for the fix**

- Gate tracer pipeline-observed state with **pipeline stall**, not retirement validity, when intent is “hold while WB is stalled.”
- Keep behavior minimal and local to tracer (avoid changing core/peripheral behavior unless clearly needed).
- Preserve existing interfaces and signal naming.

4. **How to fix**

- Update `CONNECT_CSR` macro to hold/update CSR mirrors based on `~StallW` instead of `valid`.
- Drive `rvvi.csr_wb` only when writeback is not stalled and value changed.
- Include `wfiM` in `HaltM` so tracer correctly marks halt during `wfi`.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>testbench/common/wallyTracer.sv</file>
<original>`define CONNECT_CSR(name, addr, val) \
  logic [P.XLEN-1:0] prev_csr_``name; \
  always_ff @(posedge clk) \
    prev_csr_``name <= rvvi.csr[0][0][addr]; \
  assign rvvi.csr_wb[0][0][addr] = (rvvi.csr[0][0][addr] != prev_csr_``name); \
  assign rvvi.csr[0][0][addr] = valid ? val : prev_csr_``name;</original>
<patched>`define CONNECT_CSR(name, addr, val) \
  logic [P.XLEN-1:0] prev_csr_``name; \
  always_ff @(posedge clk) \
    if (~StallW) prev_csr_``name <= rvvi.csr[0][0][addr]; \
  assign rvvi.csr_wb[0][0][addr] = ~StallW & (val != prev_csr_``name); \
  assign rvvi.csr[0][0][addr] = ~StallW ? val : prev_csr_``name;</patched>
```

# modification 2
```xml
<file>testbench/common/wallyTracer.sv</file>
<original>  assign TrapM          = testbench.dut.core.TrapM;
  assign HaltM          = testbench.DCacheFlushStart;
  if (P.ZICSR_SUPPORTED) begin</original>
<patched>  assign TrapM          = testbench.dut.core.TrapM;
  assign HaltM          = testbench.DCacheFlushStart | wfiM;
  if (P.ZICSR_SUPPORTED) begin</patched>
```