### Phase 1: FIX ANALYSIS

#### 1. What the problem is
The SPI host FSM mishandles commands when the requested CSID changes from the previous command. Instead of transitioning into the CSB-switching path, it goes to `WaitIdle`, which causes the first command after a CSID change to be skipped or delayed incorrectly.

#### 2. Where the problem occurs
The bug is in:

- `hw/vendor/lowrisc_opentitan/spi_host/rtl/spi_host_fsm.sv`

Specifically in the `WaitIdle` state logic, where the FSM decides what to do after CSB is high and the idle delay has elapsed:

- if a new command is present and `switch_required` is true, the FSM should go to `CSBSwitch`
- but the buggy behavior routes this case incorrectly in the original implementation

The relevant decision point is the `WaitIdle` branch around the `switch_required` check.

#### 3. Best practices to consider
- Make the smallest possible change that fixes the FSM transition bug.
- Preserve the intended state-machine structure and timing behavior.
- Ensure the fix matches the existing FSM design pattern used for CSB switching and idle delays.
- Avoid changing unrelated command parsing or register interface logic.

#### 4. How to fix it
In the `WaitIdle` state, when `idle_cntr_q == 4'h0` and a new command is valid with a different CSID, the FSM should transition to `CSBSwitch` instead of `WaitIdle`.

This restores the correct sequence for CSID changes and ensures the first command after a CSID switch is not skipped.

---

### Phase 2: FIX IMPLEMENTATION

```text
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