### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue is that when running **Master System (SMS) games** with a **Mega Drive controller** through standard MiSTer input mapping (not SNAC), SMS buttons are mapped as:

- SMS Button 1 ← MD **A**
- SMS Button 2 ← MD **B**

But expected behavior (matching real hardware behavior and existing SNAC behavior) is:

- SMS Button 1 ← MD **B**
- SMS Button 2 ← MD **C**

---

2. **Where the problem occurs**

The problem is in `rtl/pad_io.sv`, in the gamepad mapping logic:

```verilog
4'b1XXX: pdata <= { ~P_B,     ~P_A, ~P_RIGHT, ~P_LEFT, ~P_DOWN, ~P_UP};
```

This is the SMS mode case (`SMS=1`), and it currently maps SMS buttons to `P_B` and `P_A`.  
To match expected behavior, it should use `P_B` and `P_C` (with button 1/2 ordering preserved appropriately in this bus).

---

3. **Best practices for the fix**

- Keep the change **minimal and localized** to SMS button mapping only.
- Do **not** alter Mega Drive mode mappings, SNAC flow, or unrelated input paths.
- Preserve existing signal polarity and bus packing style (`~P_*` active-low encoding).
- Avoid UI/config string changes unless absolutely needed.

---

4. **How to fix**

Update the SMS case in `pad_io.sv` from:

- `{ ~P_B, ~P_A, ... }`

to:

- `{ ~P_C, ~P_B, ... }`

This ensures SMS button mapping becomes B/C instead of A/B for MiSTer-mapped controllers.

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