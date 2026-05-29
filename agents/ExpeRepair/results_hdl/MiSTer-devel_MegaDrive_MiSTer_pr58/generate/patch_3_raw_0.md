### Phase 1: FIX ANALYSIS

1. **Problem summary**

For Master System mode, when using MiSTer-mapped controllers in this core, SMS buttons are effectively mapped as:

- SMS 1 → Mega Drive **A**
- SMS 2 → Mega Drive **B**

But expected/real hardware behavior (and SNAC behavior) is:

- SMS 1 → Mega Drive **B**
- SMS 2 → Mega Drive **C**

So the in-core digital pad mapping for SMS mode is off by one button (shifted toward A/B instead of B/C).

2. **Where the bug is**

The issue is in `rtl/pad_io.sv`, in the gamepad output mux:

```sv
4'b1XXX: pdata <= { ~P_B,     ~P_A, ~P_RIGHT, ~P_LEFT, ~P_DOWN, ~P_UP};
```

This is the `SMS` path (`SMS=1`) and currently uses `P_B` and `P_A` for the two SMS buttons.

3. **Best practices for the fix**

- Keep the fix minimal and localized to SMS mapping logic.
- Avoid changing global controller definitions or unrelated input modes.
- Preserve existing MD/6-button/mouse/gun behavior.
- Match hardware/SNAC-consistent semantics (SMS uses MD B/C).

4. **How to fix**

Change the SMS case in `pad_io.sv` to output `P_C` and `P_B` instead of `P_B` and `P_A` for the two action bits.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>rtl/pad_io.sv</file>
<original>always @(posedge clk) begin
	priority casex({SMS,JCNT,TH})
		4'b1XXX: pdata <= { ~P_B,     ~P_A, ~P_RIGHT, ~P_LEFT, ~P_DOWN, ~P_UP}; 
		4'b0100: pdata <= { ~P_START, ~P_A,   1'b0,     1'b0,    1'b0,   1'b0};
		4'b0110: pdata <= { ~P_START, ~P_A,   1'b1,     1'b1,    1'b1,   1'b1};
		4'b0111: pdata <= { ~P_C,     ~P_B, ~P_MODE,  ~P_X,    ~P_Y,    ~P_Z };
		4'b0XX1: pdata <= { ~P_C,     ~P_B, ~P_RIGHT, ~P_LEFT, ~P_DOWN, ~P_UP};
		4'b0XX0: pdata <= { ~P_START, ~P_A,   1'b0,     1'b0,  ~P_DOWN, ~P_UP};
	endcase
end</original>
<patched>always @(posedge clk) begin
	priority casex({SMS,JCNT,TH})
		4'b1XXX: pdata <= { ~P_C,     ~P_B, ~P_RIGHT, ~P_LEFT, ~P_DOWN, ~P_UP}; 
		4'b0100: pdata <= { ~P_START, ~P_A,   1'b0,     1'b0,    1'b0,   1'b0};
		4'b0110: pdata <= { ~P_START, ~P_A,   1'b1,     1'b1,    1'b1,   1'b1};
		4'b0111: pdata <= { ~P_C,     ~P_B, ~P_MODE,  ~P_X,    ~P_Y,    ~P_Z };
		4'b0XX1: pdata <= { ~P_C,     ~P_B, ~P_RIGHT, ~P_LEFT, ~P_DOWN, ~P_UP};
		4'b0XX0: pdata <= { ~P_START, ~P_A,   1'b0,     1'b0,  ~P_DOWN, ~P_UP};
	endcase
end</patched>
```