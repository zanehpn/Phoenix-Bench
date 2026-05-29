## Phase 1: FIX ANALYSIS

### 1) What the problem is
The SPI host FSM mishandles a command whose CSID differs from the previously executed command. In that case, the FSM enters `WaitIdle` instead of the CSID-switch path, which causes the first command after a CSID change to be skipped or delayed incorrectly.

### 2) Where the problem occurs
The bug is in:

- `hw/vendor/lowrisc_opentitan/spi_host/rtl/spi_host_fsm.sv`

Specifically in the FSM transition logic around the `IdleCSBActive` state. When a new command arrives with a different `csid`, the FSM should transition into `CSBSwitch` so it can insert the required idle cycles and reconfigure timing before proceeding. Instead, the buggy behavior transitions to `WaitIdle`.

### 3) Best practices to take into account
- Keep the fix minimal and localized to the FSM transition logic.
- Preserve existing state machine semantics and timing guarantees.
- Ensure CSID switching still respects idle delay requirements and configuration changes.
- Match the intended design behavior already reflected in upstream OpenTitan logic.

### 4) How to fix it
Change the transition for the CSID-mismatch path so that the FSM enters `CSBSwitch` rather than `WaitIdle`. This ensures the FSM performs the proper extra idle-cycle handling before accepting the next command on the new CSID.

---

## Phase 2: FIX IMPLEMENTATION

```diff
<file>hw/vendor/lowrisc_opentitan/spi_host/rtl/spi_host_fsm.sv</file>
<original>
          if (idle_cntr_q == 4'h0) begin
            prestall_st_d = WaitLead;
          end else begin
            prestall_st_d = WaitIdle;
          end
        end
</original>
<patched>
          if (idle_cntr_q == 4'h0) begin
            prestall_st_d = WaitLead;
          end else begin
            prestall_st_d = CSBSwitch;
          end
        end
</patched>
```

