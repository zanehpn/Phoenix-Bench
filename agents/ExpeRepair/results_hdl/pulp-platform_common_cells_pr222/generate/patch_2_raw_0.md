### Phase 1: FIX ANALYSIS

1. **Problem statement**

`stream_arbiter_flushable` configures `rr_arb_tree` for `ARBITER == "prio"` with:
- `ExtPrio = 1'b1`
- `LockIn  = 1'b1`

But `rr_arb_tree` explicitly forbids this combination with:
```systemverilog
assert(!(LockIn && ExtPrio))
```
So any priority stream arbiter instance triggers a fatal assertion.

2. **Where it occurs**

- In `src/stream_arbiter_flushable.sv`, inside `gen_prio_arb` (the `ARBITER == "prio"` branch), `rr_arb_tree` is instantiated with `ExtPrio` and `LockIn` both enabled.
- In `src/rr_arb_tree.sv`, assertion `assert(!(LockIn && ExtPrio))` rejects that parameter combination.

3. **Best practices for the fix**

- Keep behavior intent (`"prio"` should remain priority arbitration).
- Respect downstream module contracts/assertions (do not instantiate illegal parameter combinations).
- Make minimal changes localized to the incorrect instantiation.
- Preserve stream interface stability behavior (`LockIn` should remain enabled for AXI-style stream semantics).

4. **How to fix**

For `"prio"` mode in `stream_arbiter_flushable`:
- Disable `ExtPrio` (`1'b0`) to satisfy `rr_arb_tree` assertion.
- Enable `FairArb = 1'b0` to realize static/fixed-priority behavior without external priority override.
- Keep `LockIn = 1'b1` and `AxiVldRdy = 1'b1` unchanged.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/stream_arbiter_flushable.sv</file>
<original>  end else if (ARBITER == "prio") begin : gen_prio_arb
    rr_arb_tree #(
      .NumIn      (N_INP),
      .DataType   (DATA_T),
      .ExtPrio    (1'b1),
      .AxiVldRdy  (1'b1),
      .LockIn     (1'b1)
    ) i_arbiter (
      .clk_i,
      .rst_ni,
      .flush_i,
      .rr_i   ('0),
      .req_i  (inp_valid_i),
      .gnt_o  (inp_ready_o),
      .data_i (inp_data_i),
      .gnt_i  (oup_ready_i),
      .req_o  (oup_valid_o),
      .data_o (oup_data_o),
      .idx_o  ()
    );</original>
<patched>  end else if (ARBITER == "prio") begin : gen_prio_arb
    rr_arb_tree #(
      .NumIn      (N_INP),
      .DataType   (DATA_T),
      .ExtPrio    (1'b0),
      .AxiVldRdy  (1'b1),
      .LockIn     (1'b1),
      .FairArb    (1'b0)
    ) i_arbiter (
      .clk_i,
      .rst_ni,
      .flush_i,
      .rr_i   ('0),
      .req_i  (inp_valid_i),
      .gnt_o  (inp_ready_o),
      .data_i (inp_data_i),
      .gnt_i  (oup_ready_i),
      .req_o  (oup_valid_o),
      .data_o (oup_data_o),
      .idx_o  ()
    );</patched>
```