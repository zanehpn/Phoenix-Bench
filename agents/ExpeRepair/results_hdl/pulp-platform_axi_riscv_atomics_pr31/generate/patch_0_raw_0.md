## Phase 1: FIX ANALYSIS

### 1) What the problem is
The `axi_riscv_lrsc` module computes the number of reservation-clear operations for AXI write bursts incorrectly.

For an AW burst of length `N`, it currently clears/checks `N+1` addresses instead of the correct `N` addresses in the range:

- current behavior: `[A, A + N]`
- correct behavior: `[A, A + (N - 1)]`

So the burst handling over-clears by one address.

### 2) Where the problem occurs
The bug is in `src/axi_riscv_lrsc.sv`, in the AW-channel handling logic where the code initializes `clr_len_d` for burst writes.

The relevant logic is in the `AW_IDLE` branch, around the section:

```verilog
if (aw_res_len > 1) begin
    clr_addr_d = slv_aw_addr_i[AXI_ADDR_WIDTH-1:AXI_ADDR_LSB] + 1;
    clr_len_d  = aw_res_len - 1;
```

and then in `AW_BURST` the module repeatedly clears addresses until `clr_len_q` reaches zero.

Because `clr_len_d` is set to `aw_res_len - 1`, and the starting address is already included in the first clear request, the module ends up clearing one extra address.

### 3) Best practices to take into account
- Keep the fix minimal and localized.
- Preserve the existing AW burst state-machine behavior.
- Ensure the number of generated clear requests exactly matches the intended burst address span.
- Avoid changing unrelated logic or interfaces.
- Maintain the current semantics for non-burst and single-beat transactions.

### 4) How to fix the problem
Adjust the initial clear-length calculation so the burst clear loop iterates over exactly the remaining addresses after the first one.

Since the first address is handled immediately, the remaining number of addresses is `aw_res_len - 2`, not `aw_res_len - 1`.

So change:

```verilog
clr_len_d  = aw_res_len - 1;
```

to:

```verilog
clr_len_d  = aw_res_len - 2;
```

This ensures a burst of length `N` clears exactly `N` addresses total.

---

## Phase 2: FIX IMPLEMENTATION

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