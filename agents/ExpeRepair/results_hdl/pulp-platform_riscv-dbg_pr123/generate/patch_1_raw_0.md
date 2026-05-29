## Phase 1: FIX ANALYSIS

### 1. Problem summary
The issue is that the new `trst_no` generation logic in `dmi_jtag_tap.sv` is unsafe. It is driven by a combinationally-derived signal (`trst_sync1`) and then used as an asynchronous reset in other modules (`dmi_jtag.sv`, `dmi_cdc.sv`). Because `trst_no` is updated inside a clocked process using intermediate signals that are also driven combinatorially from TAP state logic, it can glitch or assert/deassert unpredictably.

This is especially dangerous because asynchronous reset inputs must be clean and monotonic; glitches can cause partial resets, metastability, or inconsistent state across modules.

### 2. Where the problem occurs
The problematic logic is in:

- `src/dmi_jtag_tap.sv`
- Specifically the block around:
  - `logic trst_sync1, trst_sync2;`
  - the `always_ff @(posedge tck_i or negedge trst_ni)` block assigning `trst_no`
  - the `always_comb` block that assigns `trst_sync1 = trst_ni;` and overrides it in `TestLogicReset`

The unsafe part is that `trst_no` is being generated from logic that depends on TAP FSM combinational state, rather than being synchronized cleanly and deterministically.

### 3. Best practices to take into account
- Do not feed combinational or FSM-derived signals directly into asynchronous resets.
- If a reset must be generated from a state machine, make it synchronous and registered.
- Keep reset generation and state-machine outputs clearly separated.
- Avoid mixing combinational assignments and sequential reset generation for the same control signal.
- Ensure any reset-like signal used outside the module is stable and glitch-free.

### 4. How to fix it
The safest fix is to remove the glitch-prone `trst_no` generation logic based on the TAP state and instead ensure `trst_no` is driven only from the external JTAG reset input in a stable way.

Given the described issue, the minimum safe correction is:
- eliminate the special `TestLogicReset`-based synthesis of `trst_no`
- keep `trst_no` as a clean reset derived directly from `trst_ni` (or remove the extra logic entirely if it was only intended for that feature)

This preserves a stable asynchronous reset path and avoids glitching from TAP FSM transitions.

---

## Phase 2: FIX IMPLEMENTATION

### Modification 1
```diff
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
assign trst_no = trst_ni;
</patched>
```

### Modification 2
```diff
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

    unique case (tap_state_q)
      TestLogicReset: begin
        tap_state_d = (tms_i) ? TestLogicReset : RunTestIdle;
        trst_sync1 = 1'b1;
      end
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

    unique case (tap_state_q)
      TestLogicReset: begin
        tap_state_d = (tms_i) ? TestLogicReset : RunTestIdle;
      end
</patched>
```