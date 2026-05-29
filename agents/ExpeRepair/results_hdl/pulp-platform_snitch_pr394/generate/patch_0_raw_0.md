## Phase 1: FIX ANALYSIS

### 1. What the problem is
The SPI host FSM incorrectly handles a command that targets a different CSID than the previous command.  
Instead of transitioning into the dedicated `CSBSwitch` state, the FSM goes to `WaitIdle`, which causes it to effectively skip the first command after a CSID change.

This means the first command after switching chip select can be missed or delayed incorrectly, breaking correct multi-device operation.

### 2. Where the problem occurs
The bug is in:

- `hw/vendor/lowrisc_opentitan/spi_host/rtl/spi_host_fsm.sv`

Specifically, in the `WaitIdle` state handling, where the FSM decides what to do after idle delay expires and a new command is present.

Relevant logic:
- `switch_required` is already computed as `command_valid_i && (command_i.csid != csid_q)`
- In `WaitIdle`, when `idle_cntr_q == 0` and `command_valid_i` is true, the FSM should enter `CSBSwitch` if `switch_required` is true.

The buggy behavior is that this path previously went to `WaitIdle` instead of `CSBSwitch`.

### 3. Best practices to take into account
- Make the smallest possible change to fix the state transition.
- Preserve existing FSM structure and timing behavior.
- Use the existing `switch_required` signal rather than duplicating CSID comparison logic.
- Ensure the change matches the intended FSM semantics for CSID switching.
- Avoid changes in unrelated files unless necessary.

### 4. How to fix the problem
Modify the `WaitIdle` state transition so that when a new command arrives with a different CSID, the FSM transitions to `CSBSwitch` instead of `WaitIdle`.

That is:
- change the `prestall_st_d` assignment in the `switch_required` branch from `WaitIdle` to `CSBSwitch`.

---

## Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>hw/vendor/lowrisc_opentitan/spi_host/rtl/spi_host_fsm.sv</file>
<original>
          if (idle_cntr_q == 4'h0) begin
            prestall_st_d = WaitLead;
          end else begin
            prestall_st_d = WaitIdle;
          end
</original>
<patched>
          if (idle_cntr_q == 4'h0) begin
            prestall_st_d = WaitLead;
          end else begin
            prestall_st_d = CSBSwitch;
          end
</patched>
```

