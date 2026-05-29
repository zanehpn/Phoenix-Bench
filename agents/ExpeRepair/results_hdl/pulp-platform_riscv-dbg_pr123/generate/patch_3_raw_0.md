## Phase 1: FIX ANALYSIS

### 1) What the problem is
The issue is that `dmi_jtag_tap.sv` generates `trst_no` using logic that is clocked by `tck_i` and depends on a combinational signal (`trst_sync1`) derived from TAP state logic. This makes `trst_no` prone to glitches and incorrect transient values. Since `trst_no` is used as an asynchronous reset in `dmi_jtag.sv` and `dmi_cdc.sv`, a glitch can unintentionally reset those modules.

In short:
- The intent is to reset the JTAG/DMI logic by cycling TMS into `TestLogicReset`.
- The implementation of the generated reset is unsafe.
- `trst_no` should not be derived in a way that can glitch or behave asynchronously from combinational state changes.

### 2) Where the problem occurs
The problematic code is in:

- `src/dmi_jtag_tap.sv`

Specifically the block:

```systemverilog
logic trst_sync1, trst_sync2;

always_ff @(posedge tck_i or negedge trst_ni) begin
  if (!trst_ni) begin
    trst_sync2 <= 1'b0;
  end else begin
    trst_sync2 <= trst_sync1;
    trst_no    <= trst_sync2;
  end
end
```

and its dependency here:

```systemverilog
always_comb begin : p_tap_fsm
  trst_sync1         = trst_ni;
  ...
  TestLogicReset: begin
    ...
    trst_sync1 = 1'b1;
  end
```

The combination of:
- `trst_sync1` being assigned in combinational logic,
- `trst_no` being driven from a sequential block but not cleanly synchronized,
- and `trst_no` effectively acting like an asynchronous reset,

is what makes the design unsafe.

### 3) Best practices to take into account
The fix should follow these principles:

- **Do not generate asynchronous reset-like signals from combinational state transitions** unless absolutely necessary and fully synchronized.
- **Avoid glitch-prone reset generation** from mixed combinational/sequential logic.
- **Use a clean, registered reset signal** if the goal is to reset based on TAP state.
- **Keep reset generation synchronous to the relevant clock** (`tck_i`) to ensure stable behavior.
- **Minimize changes** and preserve intended functionality.

### 4) How to fix the problem
The safest fix is to remove the unsafe generated-reset behavior and instead keep `trst_no` directly tied to the external reset (`trst_ni`) or implement a fully synchronous reset scheme.

Given the issue description and the minimal-change requirement, the best fix is:

- Remove the logic that tries to create `trst_no` by cycling through `TestLogicReset`.
- Keep `trst_no` stable and non-glitchy by assigning it directly from `trst_ni` or otherwise ensuring it is only updated synchronously in a safe way.

This avoids unintended asynchronous resets in downstream modules.

---

## Phase 2: FIX IMPLEMENTATION

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
logic trst_sync1, trst_sync2;

assign trst_no = trst_ni;
</patched>
```

```diff
<file>src/dmi_jtag_tap.sv</file>
<original>
    unique case (tap_state_q)
      TestLogicReset: begin
        tap_state_d = (tms_i) ? TestLogicReset : RunTestIdle;
        trst_sync1 = 1'b1;
      end
      RunTestIdle: begin
        tap_state_d = (tms_i) ? SelectDrScan : RunTestIdle;
      end
</original>
<patched>
    unique case (tap_state_q)
      TestLogicReset: begin
        tap_state_d = (tms_i) ? TestLogicReset : RunTestIdle;
      end
      RunTestIdle: begin
        tap_state_d = (tms_i) ? SelectDrScan : RunTestIdle;
      end
</patched>
```

