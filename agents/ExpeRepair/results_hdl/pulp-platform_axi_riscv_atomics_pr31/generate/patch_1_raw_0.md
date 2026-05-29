### Phase 1: FIX ANALYSIS

#### 1. What the problem is
The `axi_riscv_lrsc` module incorrectly computes the range of addresses to check and clear for an AXI write burst.

For a burst of length `N` starting at address `A`, it currently clears addresses `[A, A+N]`, but the correct range is `[A, A+(N-1)]`.

In other words, the logic clears one extra address beyond the burst.

#### 2. Where the problem occurs
The bug is in `src/axi_riscv_lrsc.sv`, in the AW burst handling logic.

The relevant code is in the `AW_IDLE` branch where a burst write is detected and the clear-range tracking is initialized:

- `clr_addr_d` is set to the start address offset
- `clr_len_d` is derived from `aw_res_len`

The specific issue is here:

```verilog
if (aw_res_len > 1) begin
    clr_addr_d = slv_aw_addr_i[AXI_ADDR_WIDTH-1:AXI_ADDR_LSB] + 1;
    clr_len_d  = aw_res_len - 1;
```

Given the loop in `AW_BURST`, this initialization causes one too many addresses to be checked/cleared.

#### 3. Best practices to take into account
- Keep the fix minimal and localized.
- Preserve existing burst handling and state-machine behavior.
- Ensure the clear-range logic matches the intended inclusive address range.
- Avoid changing unrelated logic unless necessary.
- Maintain consistency with how `clr_addr_q` and `clr_len_q` are consumed in `AW_BURST`.

#### 4. How to fix the problem
Adjust the initial clear length so that the total number of cleared addresses matches the actual burst coverage.

For bursts with `aw_res_len > 1`, the initial remaining length should be reduced by one more, i.e.:

- from `clr_len_d = aw_res_len - 1;`
- to `clr_len_d = aw_res_len - 2;`

This way, the first address is handled immediately, and the remaining loop clears exactly the remaining burst addresses without overshooting by one.

---

### Phase 2: FIX IMPLEMENTATION

```verilog
<file>src/axi_riscv_lrsc.sv</file>
<original>
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