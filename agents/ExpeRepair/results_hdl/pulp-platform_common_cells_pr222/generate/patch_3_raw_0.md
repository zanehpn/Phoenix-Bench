### Phase 1: FIX ANALYSIS

1. **Problem summary**

`stream_arbiter_flushable` configures the `"prio"` mode by instantiating `rr_arb_tree` with:
- `ExtPrio = 1'b1`
- `LockIn  = 1'b1`

But `rr_arb_tree` explicitly forbids this combination and asserts:

```systemverilog
assert(!(LockIn && ExtPrio))
  else $fatal(1,"Cannot use LockIn feature together with external ExtPrio.");
```

So any `"prio"` stream arbiter triggers an inherent fatal assertion.

2. **Where it happens**

- In `src/stream_arbiter_flushable.sv`, `"prio"` branch:
  - `.ExtPrio(1'b1)`
  - `.LockIn(1'b1)`  ← conflicting setting
- In `src/rr_arb_tree.sv`, assertion disallowing `LockIn && ExtPrio`.

3. **Best practices for the fix**

- Keep changes minimal and localized.
- Respect submodule parameter constraints (`rr_arb_tree` contract).
- Avoid broad behavioral refactors unless necessary for this issue.
- Preserve existing interfaces and hierarchy.

4. **Fix approach**

In the `"prio"` instantiation of `rr_arb_tree`, set `LockIn` to `1'b0` so the configuration is legal (`ExtPrio=1`, `LockIn=0`) and no fatal assertion is triggered.

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
      .ExtPrio    (1'b1),
      .AxiVldRdy  (1'b1),
      .LockIn     (1'b0)
    ) i_arbiter (</patched>
```