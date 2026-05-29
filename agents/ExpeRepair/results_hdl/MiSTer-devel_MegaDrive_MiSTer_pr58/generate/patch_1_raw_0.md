### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue is that in **SMS mode**, when using MiSTer-mapped controllers in the Mega Drive core, SMS buttons are mapped as:

- SMS 1 ← MD **A**
- SMS 2 ← MD **B**

But expected hardware-accurate behavior (and SNAC behavior) is:

- SMS 1 ← MD **B**
- SMS 2 ← MD **C**

---

2. **Where it occurs**

The incorrect mapping is in `rtl/pad_io.sv`, inside the gamepad output logic for SMS mode:

```verilog
4'b1XXX: pdata <= { ~P_B, ~P_A, ~P_RIGHT, ~P_LEFT, ~P_DOWN, ~P_UP};
```

This SMS branch currently uses `P_A` and `P_B`.  
It should use `P_B` and `P_C`.

---

3. **Best practices for the fix**

- Keep the patch **minimal** and scoped to SMS-only behavior.
- Do not alter Mega Drive mode mappings or unrelated input paths.
- Preserve existing signal polarity (active-low button encoding).
- Match expected original hardware behavior and existing SNAC behavior.

---

4. **How to fix**

Update the SMS mapping line in `pad_io.sv` so that SMS buttons are driven from MD `B` and `C` instead of `A` and `B`:

- from `{~P_B, ~P_A, ...}`
- to   `{~P_C, ~P_B, ...}`

This shifts SMS button 1/2 sources to B/C as desired.

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