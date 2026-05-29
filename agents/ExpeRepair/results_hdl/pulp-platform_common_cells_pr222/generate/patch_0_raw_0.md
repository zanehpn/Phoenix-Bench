### Phase 1: FIX ANALYSIS

1. **Problem summary**

`stream_arbiter_flushable` configures `rr_arb_tree` in `"prio"` mode with:
- `ExtPrio = 1'b1`
- `LockIn  = 1'b1`

But `rr_arb_tree` explicitly forbids this combination (`assert(!(LockIn && ExtPrio))`), so every `"prio"` stream arbiter instance triggers a fatal assertion at elaboration/sim startup.

2. **Where it occurs**

The issue is in `src/stream_arbiter_flushable.sv`, in the `gen_prio_arb` branch:
```systemverilog
.ExtPrio    (1'b1),
.AxiVldRdy  (1'b1),
.LockIn     (1'b1)
```
This conflicts with the assertion in `src/rr_arb_tree.sv`.

3. **Best practices for the fix**

- Keep changes **minimal** and localized to the faulty instantiation.
- Preserve stream-arbiter behavior (especially stable selection under backpressure, i.e. `LockIn` semantics).
- Use supported `rr_arb_tree` parameter combinations only.

4. **How to fix**

For `"prio"` arbitration, use internal arbitration mode with fairness disabled:
- `ExtPrio = 1'b0`
- `FairArb = 1'b0`
- keep `LockIn = 1'b1`

This removes the illegal combination while maintaining static-priority behavior and lock-in behavior expected by stream arbitration.

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