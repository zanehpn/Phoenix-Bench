## Phase 1: FIX ANALYSIS

### 1. What the problem is
The issue is that when `trst_ni` is asserted low, the TAP state machine is being reset to `RunTestIdle`, but according to IEEE 1149.1 the TAP controller must reset to `Test-Logic-Reset`.

So the current reset behavior is incorrect for JTAG TAP state handling.

### 2. Where the problem occurs
The bug is in `src/dmi_jtag_tap.sv`, inside the sequential TAP state register update block:

- **Location #2 / #3**
  ```systemverilog
  always_ff @(posedge tck_i or negedge trst_ni) begin : p_regs
    if (!trst_ni) begin
      tap_state_q <= RunTestIdle;
  ```
This is the state reset assignment that must be changed.

### 3. Best practices to take into account
- Follow the IEEE 1149.1 TAP reset semantics: asynchronous reset should bring the TAP to `TestLogicReset`.
- Keep the fix minimal and localized.
- Do not alter unrelated reset behavior for `idcode_q` or `bypass_q` unless needed.
- Ensure the TAP state machine’s reset state is consistent with the combinational FSM logic and with `test_logic_reset` signaling.

### 4. How to fix the problem
Change the reset assignment of `tap_state_q` from `RunTestIdle` to `TestLogicReset` in the asynchronous reset branch of the TAP registers process.

This makes the TAP controller conform to the standard and aligns with the intent described in the issue.

---

## Phase 2: FIX IMPLEMENTATION

```patch
<file>src/dmi_jtag_tap.sv</file>
<original>
  always_ff @(posedge tck_i or negedge trst_ni) begin : p_regs
    if (!trst_ni) begin
      tap_state_q <= RunTestIdle;
      idcode_q    <= IdcodeValue;
      bypass_q    <= 1'b0;
    end else begin
      tap_state_q <= tap_state_d;
      idcode_q    <= idcode_d;
      bypass_q    <= bypass_d;
    end
  end
</original>
<patched>
  always_ff @(posedge tck_i or negedge trst_ni) begin : p_regs
    if (!trst_ni) begin
      tap_state_q <= TestLogicReset;
      idcode_q    <= IdcodeValue;
      bypass_q    <= 1'b0;
    end else begin
      tap_state_q <= tap_state_d;
      idcode_q    <= idcode_d;
      bypass_q    <= bypass_d;
    end
  end
</patched>
```

