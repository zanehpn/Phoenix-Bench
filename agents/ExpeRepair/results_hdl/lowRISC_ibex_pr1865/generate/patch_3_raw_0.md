### Phase 1: FIX ANALYSIS

#### 1. What the problem is
The issue is that in lockstep mode, the `core_busy_o` signal of the non-lockstep core is used to gate the shared core clock. Since the lockstep core is clocked by the same gated clock, it can be turned off in the same cycle that the main core’s `core_busy_o` glitches low.

As a result, a transient low glitch on `core_busy_o` may stop the lockstep core from sampling the faulty value, so the mismatch is not detected and no major alert is raised.

#### 2. Where the problem occurs
The relevant behavior is in `rtl/ibex_top.sv`:

- `clock_en` is derived from `core_busy_q`
- `clock_en` drives the clock gate
- both `u_ibex_core` and `u_ibex_lockstep` use the gated clock `clk`

This is the problematic path:

- `core_busy_q` controls `clock_en`
- `clock_en` gates `clk`
- `clk` feeds both cores
- lockstep core may be disabled too early to compare the bad `core_busy_o`

The comparison logic in `rtl/ibex_lockstep.sv` is not the root cause; it only compares sampled outputs, so if the lockstep core is not clocked at the right time, the mismatch cannot be observed.

#### 3. Best practices to take into account
- Do not let the lockstep monitor be clock-gated by the signal it is supposed to verify.
- The checker/lockstep path should remain observable when the monitored output changes.
- Keep the fix minimal and localized to the clock-gating/control path.
- Preserve existing behavior outside lockstep operation as much as possible.

#### 4. How to fix the problem
The clock-gating enable used for the shared clock must be decoupled from the potentially faulty `core_busy_o` signal when lockstep checking is active.

A robust minimal fix is to ensure the lockstep comparison can still be evaluated before the clock is gated off. In practice, this means adjusting the clock-enable logic so the lockstep core is not disabled in the same cycle as the main core’s `core_busy_o` transition. The most appropriate location is `rtl/ibex_top.sv`, where the shared clock is generated and distributed to both cores.

---

### Phase 2: FIX IMPLEMENTATION

Below is a minimal patch that addresses the issue by preventing the shared clock from being gated solely by the possibly-glitchy `core_busy_q` signal when lockstep monitoring is present.

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
 
  // Keep the shared clock alive long enough for lockstep comparison to observe
  // any transient mismatch on core_busy_o.
  assign clock_en_safe = clock_en | ~core_sleep_o;
 
  prim_clock_gating core_clock_gate_i (
    .clk_i    (clk_i),
    .en_i     (clock_en_safe),
    .test_en_i(test_en_i),
    .clk_o    (clk)
  );
</patched>
```

