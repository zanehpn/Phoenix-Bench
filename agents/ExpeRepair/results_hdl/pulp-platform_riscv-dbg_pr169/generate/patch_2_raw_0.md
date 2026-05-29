## Phase 1: FIX ANALYSIS

### 1. What the problem is
The TAP reset behavior on `trst_ni` is incorrect.

According to IEEE 1149.1, asserting `TRST` should force the TAP controller into the **Test-Logic-Reset** state, not **Run-Test/Idle**.

In the current implementation, the asynchronous reset of the TAP state machine initializes the state register to `RunTestIdle`, which violates the JTAG specification and can prevent the expected reset behavior from propagating correctly.

---

### 2. Where the problem occurs
The bug is in `src/dmi_jtag_tap.sv`, specifically in the TAP state register reset logic:

- **Location #2** is the primary buggy location:
  ```systemverilog
  if (!trst_ni) begin
    tap_state_q <= RunTestIdle;
  end
  ```
  This should reset to `TestLogicReset`.

- **Location #3** is effectively the same code region, just an overlapping snippet.
  It is not a separate bug, just another view of the same faulty reset assignment.

---

### 3. Best practices to take into account
- **Follow the IEEE 1149.1 TAP reset requirement**: `TRST` must place the TAP in `Test-Logic-Reset`.
- **Keep the fix minimal**: only change the incorrect reset state; do not alter unrelated TAP behavior.
- **Preserve existing combinational/sequential structure**: the current FSM design already handles `test_logic_reset` output in the `TestLogicReset` state, so the reset should align with that state.
- **Avoid introducing side effects**: other resettable registers (`idcode_q`, `bypass_q`) appear already correct and should remain unchanged.

---

### 4. How to fix the problem
Change the asynchronous reset value of `tap_state_q` from `RunTestIdle` to `TestLogicReset`.

This ensures that when `trst_ni` is asserted low, the TAP controller starts in the proper reset state and the FSM will behave according to the standard.

---

## Phase 2: FIX IMPLEMENTATION

# modification 1
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