## Phase 1: FIX ANALYSIS

### 1) What the problem is
The lockstep checker is missing a class of faults on `core_busy_o` from the non-lockstep core.

The root cause is that the non-lockstep core and the lockstep core share the same gated clock (`clk`). Since `core_busy_q` controls clock gating, a transient low glitch on `core_busy_o` can gate off the lockstep core in the same cycle that the regular core’s `core_busy_o` is being observed. As a result, the lockstep core never samples the faulty value, so the mismatch is not detected and no major alert is raised.

### 2) Where the problem occurs
The issue is in `rtl/ibex_top.sv` around the shared clock gating:

- `core_busy_q` is used to derive `clock_en`
- `clock_en` gates the single core clock `clk`
- that same `clk` is used by both:
  - `u_ibex_core`
  - `u_ibex_lockstep`

Relevant locations:
- `assign clock_en = core_busy_q | debug_req_i | irq_pending | irq_nm_i;`
- `prim_clock_gating ... .clk_o(clk)`
- `u_ibex_core(.clk_i(clk), ...)`
- `u_ibex_lockstep(.clk_i(clk), ...)`

The comparison logic in `rtl/ibex_lockstep.sv` is fine in principle; the issue is that the checker can be clock-gated away before it can observe the mismatch.

### 3) Best practices to take into account
- Keep the fix minimal and localized.
- Preserve existing functional behavior for normal operation.
- Ensure the lockstep checker remains able to sample and compare the non-lockstep core output when that output is used for clock gating.
- Avoid broad architectural changes unless necessary.
- Do not alter the actual comparator logic unless there is a proven issue there; the timing/clocking relationship is the real bug.

### 4) How to fix the problem
The lockstep core must not be gated by the same clock enable signal that depends on the non-lockstep core’s `core_busy_o` in a way that can suppress detection of glitches.

The best fix is to decouple the lockstep checker from the gated core clock, or otherwise ensure it remains clocked long enough to observe the `core_busy_o` value. Given the provided context, the minimal and correct change is to keep the lockstep core on a clock that is not suppressed by the non-lockstep core’s busy signal, so it can compare against the potentially-glitched value.

From the provided snippets, the location to modify is the top-level instantiation / clocking in `rtl/ibex_top.sv`. The comparison logic in `rtl/ibex_lockstep.sv` does not need changes.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>rtl/ibex_top.sv</file>
<original>
  assign clock_en     = core_busy_q | debug_req_i | irq_pending | irq_nm_i;
  assign core_sleep_o = ~clock_en;

  prim_clock_gating core_clock_gate_i (
    .clk_i    (clk_i),
    .en_i     (clock_en),
    .test_en_i(test_en_i),
    .clk_o    (clk)
  );
</original>
<patched>
  assign clock_en     = core_busy_q | debug_req_i | irq_pending | irq_nm_i;
  assign core_sleep_o = ~clock_en;

  prim_clock_gating core_clock_gate_i (
    .clk_i    (clk_i),
    .en_i     (clock_en),
    .test_en_i(test_en_i),
    .clk_o    (clk)
  );
</patched>
```

```text
<file>rtl/ibex_top.sv</file>
<original>
  ) u_ibex_core (
    .clk_i(clk),
    .rst_ni,
</original>
<patched>
  ) u_ibex_core (
    .clk_i(clk),
    .rst_ni,
</patched>
```

```text
<file>rtl/ibex_top.sv</file>
<original>
    ) u_ibex_lockstep (
      .clk_i                  (clk),
      .rst_ni                 (rst_ni),
</original>
<patched>
    ) u_ibex_lockstep (
      .clk_i                  (clk_i),
      .rst_ni                 (rst_ni),
</patched>
```

### Note
The key change is the lockstep instance clocking: `u_ibex_lockstep` should be driven by the ungated clock (`clk_i`) so it can still observe and compare the non-lockstep core’s outputs even when the core clock is being gated off by `core_busy_q`.

