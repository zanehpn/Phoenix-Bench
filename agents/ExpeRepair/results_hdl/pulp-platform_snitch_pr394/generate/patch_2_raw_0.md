## Phase 1: FIX ANALYSIS

### 1. What the problem is
The SPI host FSM incorrectly handles a command whose `csid` differs from the previous command’s `csid`.  
Instead of transitioning into the dedicated `CSBSwitch` state, it goes to `WaitIdle`, which effectively skips the first command after a CSID change. This breaks correct handling of chip-select switching timing and configuration update delays.

### 2. Where the problem occurs
The bug is in:

- `hw/vendor/lowrisc_opentitan/spi_host/rtl/spi_host_fsm.sv`

Specifically, in the `WaitIdle` state logic, at the branch that handles a valid command after the idle delay has elapsed:

- when `switch_required` is true, the FSM should go to `CSBSwitch`
- the buggy behavior occurs when it instead goes to `WaitIdle`

The relevant logic is in the `WaitIdle` state around the `switch_required` check.

### 3. Best practices to take into account
- Make the smallest possible fix to avoid unintended behavior changes.
- Preserve existing FSM structure and timing semantics.
- Ensure CSID changes still respect the required idle delay and CSB switching behavior.
- Align behavior with the intended FSM design and the reference implementation pattern.

### 4. How to fix the problem
Change the `WaitIdle` state transition for `switch_required` from `WaitIdle` to `CSBSwitch`.  
This ensures the FSM enters the special transition state that properly inserts extra idle cycles when switching CSIDs and prevents the first command after a CSID change from being skipped.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>hw/vendor/lowrisc_opentitan/spi_host/rtl/spi_host_fsm.sv</file>
<original>            if (switch_required) begin
               prestall_st_d = WaitIdle;
             end else begin
               prestall_st_d = WaitLead;
             end</original>
<patched>            if (switch_required) begin
               prestall_st_d = CSBSwitch;
             end else begin
               prestall_st_d = WaitLead;
             end</patched>
```
