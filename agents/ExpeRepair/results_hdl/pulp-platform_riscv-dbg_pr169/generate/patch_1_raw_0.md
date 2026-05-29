## Phase 1: FIX ANALYSIS

### 1. What the problem is
The TAP reset logic is incorrect for `trst_ni` reset handling.

Per IEEE 1149.1, when the TAP is reset, the TAP controller must enter the **Test-Logic-Reset** state.  
In the current design, the asynchronous reset on `trst_ni` initializes `tap_state_q` to `RunTestIdle`, which is not the correct reset state.

### 2. Where the problem occurs
The bug is in `src/dmi_jtag_tap.sv`, in the sequential TAP state register block:

- **Location #2** is the actual bug:
  ```sv
  always_ff @(posedge tck_i or negedge trst_ni) begin : p_regs
    if (!trst_ni) begin
      tap_state_q <= RunTestIdle;
  ```
  This should be `TestLogicReset`.

Related logic already exists in the combinational FSM:
- `TestLogicReset` state sets `test_logic_reset = 1'b1;`
- That signal is used to reset internal IR state and DMI clear behavior.

So the main mismatch is that the registered TAP state itself is initialized incorrectly.

### 3. Best practices to take into account
- **Follow the spec exactly**: TAP reset via `trst_ni` should map to `Test-Logic-Reset`.
- **Keep changes minimal**: only adjust the reset value, since the rest of the FSM already models reset behavior correctly.
- **Preserve existing reset side effects**: internal reset signals like `test_logic_reset` already depend on TAP state and should continue to work as-is.

### 4. How to fix the problem
Change the asynchronous reset assignment of `tap_state_q` from `RunTestIdle` to `TestLogicReset`.

That is sufficient to ensure the TAP begins in the correct reset state after `trst_ni` is asserted low.

---

## Phase 2: FIX IMPLEMENTATION

```text
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

