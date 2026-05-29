## Phase 1: FIX ANALYSIS

### 1) What the problem is
The bug is in the new TAP reset logic introduced by commit `b5d1610`. The design tries to generate `trst_no` from the JTAG TAP state machine so that cycling TMS into `TestLogicReset` can reset `dmi_jtag`. However, the implementation is unsafe because `trst_no` is driven inside logic that is not properly synchronized and is updated in a way that can glitch.

That matters because `trst_no` is used as an asynchronous reset in other modules (`dmi_jtag.sv` and `dmi_cdc.sv`). A glitch on an async reset can cause spurious resets, metastability, or inconsistent reset release across clock domains.

### 2) Where the problem occurs
The problematic code is in `src/dmi_jtag_tap.sv`, around the new `trst_sync1/trst_sync2/trst_no` logic:

- `trst_sync1` is assigned in combinational logic (`always_comb`) based on TAP state.
- `trst_sync2` and `trst_no` are updated in a clocked block.
- The current implementation mixes combinational and sequential control in a way that can produce unstable/reset-like behavior.
- In particular, `trst_no` is driven from a two-stage structure that is not a clean synchronous reset generation path.

### 3) Best practices to take into account
- Do not generate asynchronous reset signals from combinational logic that depends on state-machine outputs unless they are fully synchronized and intentionally filtered.
- If a reset must be derived from TAP state, generate it synchronously and keep its assertion/deassertion clean and clocked.
- Avoid using partially initialized or combinationally-fed intermediate signals to drive reset nets.
- Prefer a simple registered signal that is asserted when the TAP is in `TestLogicReset`, then deasserted synchronously after the state exits reset.
- Keep the fix minimal and localized.

### 4) How to fix the problem
The safest fix is to remove the glitch-prone intermediate reset-generation path and replace it with a straightforward synchronous registered reset signal derived from the TAP state:

- declare `trst_no` as a registered signal if not already done elsewhere,
- assign it only in the TAP clocked process,
- make it asserted while in `TestLogicReset`,
- deassert it synchronously once the TAP exits that state.

This avoids combinational feedback and eliminates the glitch hazard on the async reset path.

---

## Phase 2: FIX IMPLEMENTATION

```patch
<file>src/dmi_jtag_tap.sv</file>
<original>
logic trst_sync1, trst_sync2;

always_ff @(posedge tck_i or negedge trst_ni) begin
  if (!trst_ni) begin
    trst_sync2 <= 1'b0;
  end else begin
    trst_sync2 <= trst_sync1;
    trst_no    <= trst_sync2;
  end
end
</original>
<patched>
logic trst_no;

always_ff @(posedge tck_i or negedge trst_ni) begin
  if (!trst_ni) begin
    trst_no <= 1'b0;
  end else begin
    trst_no <= (tap_state_q == TestLogicReset);
  end
end
</patched>
```

```patch
<file>src/dmi_jtag_tap.sv</file>
<original>
  always_comb begin : p_tap_fsm

    trst_sync1         = trst_ni;

    capture_dr         = 1'b0;
    shift_dr           = 1'b0;
    update_dr          = 1'b0;

    capture_ir         = 1'b0;
    shift_ir           = 1'b0;
    // pause_ir           = 1'b0; unused
    update_ir          = 1'b0;
</original>
<patched>
  always_comb begin : p_tap_fsm

    capture_dr         = 1'b0;
    shift_dr           = 1'b0;
    update_dr          = 1'b0;

    capture_ir         = 1'b0;
    shift_ir           = 1'b0;
    // pause_ir           = 1'b0; unused
    update_ir          = 1'b0;
</patched>
```

