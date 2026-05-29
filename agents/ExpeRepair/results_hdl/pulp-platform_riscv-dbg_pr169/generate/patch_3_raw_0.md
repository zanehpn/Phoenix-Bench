## Phase 1: FIX ANALYSIS

### 1) What the problem is
The issue is that asserting `trst_ni` low does **not** reset the JTAG TAP state machine to the IEEE 1149.1 **Test-Logic-Reset** state.  
Instead, the code currently resets the TAP FSM state to `RunTestIdle`, which is incorrect for a TAP reset.

Per the JTAG standard, a reset via `TRST` must force the TAP controller into **Test-Logic-Reset**.

### 2) Where the problem occurs
The bug is in `src/dmi_jtag_tap.sv`, in the sequential TAP state register reset logic:

- **Location #2** is the key buggy location:
  ```systemverilog
  always_ff @(posedge tck_i or negedge trst_ni) begin : p_regs
    if (!trst_ni) begin
      tap_state_q <= RunTestIdle;
  ```
This should reset to `TestLogicReset`, not `RunTestIdle`.

### 3) Best practices to take into account
- Follow the IEEE 1149.1 requirement that `TRST` forces the TAP controller to **Test-Logic-Reset**.
- Make the change minimally and only where the behavior is wrong.
- Preserve existing behavior for other reset-sensitive signals unless they are directly affected by the TAP reset semantics.
- Ensure the combinational logic and sequential state reset remain consistent.

### 4) How to fix the problem
Change the async reset assignment of `tap_state_q` from `RunTestIdle` to `TestLogicReset` in the TAP register process.

This is sufficient because:
- The combinational FSM already defines behavior for `TestLogicReset`.
- `test_logic_reset` is asserted when the FSM is in that state, so downstream reset behavior remains aligned.

---

## Phase 2: FIX IMPLEMENTATION

```systemverilog
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