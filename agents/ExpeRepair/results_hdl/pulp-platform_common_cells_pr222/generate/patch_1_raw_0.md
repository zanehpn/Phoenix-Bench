### Phase 1: FIX ANALYSIS

1. **Problem summary**

`stream_arbiter_flushable` (and therefore `stream_arbiter`) configures `rr_arb_tree` in `"prio"` mode with:

- `ExtPrio = 1'b1`
- `LockIn  = 1'b1`

But `rr_arb_tree` has an explicit assertion that forbids this combination:
`assert(!(LockIn && ExtPrio))`.

So any `"prio"` stream arbiter instance trips a fatal assertion by construction.

2. **Where it occurs**

The problematic configuration is in `src/stream_arbiter_flushable.sv`, in the `"prio"` generate block (`gen_prio_arb`) where `rr_arb_tree` is instantiated.

3. **Best practices for the fix**

- Keep changes minimal and local to the misconfiguration.
- Do not weaken/remove safety assertions in `rr_arb_tree`; they encode valid usage constraints.
- Preserve intended `"prio"` behavior while using legal parameter combinations.
- Prefer a configuration that still allows lock-in behavior for stream stability.

4. **How to fix**

For `"prio"` mode, avoid `ExtPrio=1` and instead use internal arbitration in non-fair mode:

- Set `ExtPrio = 1'b0`
- Keep `LockIn = 1'b1`
- Add `FairArb = 1'b0` to make arbitration priority-based (non-round-robin)

This removes the illegal combo and keeps lock-in capability.

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
    ) i_arbiter (</original>
<patched>  end else if (ARBITER == "prio") begin : gen_prio_arb
    rr_arb_tree #(
      .NumIn      (N_INP),
      .DataType   (DATA_T),
      .ExtPrio    (1'b0),
      .AxiVldRdy  (1'b1),
      .LockIn     (1'b1),
      .FairArb    (1'b0)
    ) i_arbiter (</patched>
```