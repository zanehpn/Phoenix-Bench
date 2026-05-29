## Phase 1: FIX ANALYSIS

### 1) What is the problem?
The issue is an off-by-one error in `axi_riscv_lrsc`: when handling an AXI write burst of length `N`, the module issues a check-and-clear sequence for `N+1` addresses instead of the intended `N` addresses.

For a burst starting at address `A`, the module currently clears:
- `[A, A+N]`

but it should clear:
- `[A, A+(N-1)]`

This means one extra address beyond the burst is being checked/cleared.

### 2) Where does it occur?
The bug is in `src/axi_riscv_lrsc.sv`, in the AW burst handling logic, specifically around the code that initializes the clear length for burst writes:

- **Location #2** is the relevant spot:
  - It sets `clr_addr_d = slv_aw_addr_i[...] + 1;`
  - It sets `clr_len_d = aw_res_len - 1;`

Given the burst-clear loop in **Location #3**, the state machine clears one address per iteration starting from `clr_addr_q`, so the initial address/length setup determines the exact address range. The current initialization causes one extra address to be included.

### 3) Best practices to consider
- **Minimize the patch**: only adjust the logic responsible for the off-by-one error.
- **Preserve existing burst-state behavior**: do not alter unrelated AW/W/B channel flow.
- **Keep semantics consistent**: the clear loop in `AW_BURST` should cover exactly the burst-covered addresses, no more.
- **Avoid broad refactoring**: this is a targeted logic fix, not a design change.

### 4) How to fix it?
The correct fix is to adjust the initialization of the clear length in the AW burst path so that the clearing loop covers exactly the burst length.

Concretely, in the AW handling logic, change:
- `clr_len_d = aw_res_len - 1;`

to:
- `clr_len_d = aw_res_len - 2;`

This matches the issue description and ensures the resulting cleared address range is `[A, A+(N-1)]` rather than `[A, A+N]`.

---

## Phase 2: FIX IMPLEMENTATION

```text
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

