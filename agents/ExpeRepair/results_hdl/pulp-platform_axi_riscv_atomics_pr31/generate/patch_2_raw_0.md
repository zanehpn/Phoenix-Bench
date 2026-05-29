### Phase 1: FIX ANALYSIS

#### 1) What the problem is
The `axi_riscv_lrsc` module incorrectly clears one extra address when handling an AXI write burst.

For a burst with:
- start address `A`
- length `N` beats

the module currently issues check+clear requests for addresses:
- `[A, A+N]`

but the correct range is:
- `[A, A+(N-1)]`

So the last address is being cleared unnecessarily.

#### 2) Where the problem occurs
The bug is in `src/axi_riscv_lrsc.sv`, in the AW channel handling logic where the module computes how many addresses to clear for a burst.

The relevant code is in the `AW_IDLE` path, specifically here:

```verilog
if (aw_res_len > 1) begin
    clr_addr_d = slv_aw_addr_i[AXI_ADDR_WIDTH-1:AXI_ADDR_LSB] + 1;
    clr_len_d  = aw_res_len - 1;
```

The logic initializes the clear range starting at `A+1` and sets the remaining length to `aw_res_len - 1`, which causes the module to clear one too many addresses overall.

#### 3) Best practices to take into account
- Make the smallest possible change that fixes the off-by-one error.
- Preserve existing behavior for non-burst and single-beat cases.
- Keep the state machine and handshake logic unchanged unless required.
- Ensure the fix matches the intended semantics of clearing exactly the burst-covered addresses, no more.
- Avoid introducing unrelated refactoring.

#### 4) How to fix the problem
Adjust the clear-length initialization so that the clear sequence covers exactly the remaining addresses after the first one is handled.

Since the code already starts clearing from `A+1`, the number of additional addresses to clear should be `aw_res_len - 2`, not `aw_res_len - 1`.

This makes the total cleared range:
- first address: `A`
- remaining addresses: `A+1 ... A+(N-1)`

for a total of exactly `N` addresses, matching the burst length.

---

### Phase 2: FIX IMPLEMENTATION

```text
<file>src/axi_riscv_lrsc.sv</file>
<original>
                                        // Is this write longer than our reservation granularity?
                                        if (aw_res_len > 1) begin
                                            // latch start address and length of write (burst)
                                            clr_addr_d = slv_aw_addr_i[AXI_ADDR_WIDTH-1:AXI_ADDR_LSB] + 1;
                                            clr_len_d  = aw_res_len - 1;
                                            clr_id_d   = slv_aw_id_i;
                                            aw_wait_d  = ~mst_aw_ready;
                                            aw_state_d = AW_BURST;
                                        end
</original>
<patched>
                                        // Is this write longer than our reservation granularity?
                                        if (aw_res_len > 1) begin
                                            // latch start address and length of write (burst)
                                            clr_addr_d = slv_aw_addr_i[AXI_ADDR_WIDTH-1:AXI_ADDR_LSB] + 1;
                                            clr_len_d  = aw_res_len - 2;
                                            clr_id_d   = slv_aw_id_i;
                                            aw_wait_d  = ~mst_aw_ready;
                                            aw_state_d = AW_BURST;
                                        end
</patched>
```