### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue is that when playing **Master System (SMS)** games with MiSTer-mapped controllers in the Mega Drive core, SMS buttons are mapped as:

- SMS 1 -> Mega Drive **A**
- SMS 2 -> Mega Drive **B**

But expected behavior (and what happens with real/SNAC pads) is:

- SMS 1 -> Mega Drive **B**
- SMS 2 -> Mega Drive **C**

---

2. **Where it occurs**

The bug is in `rtl/pad_io.sv`, in the SMS branch of the pad output mapping:

```sv
4'b1XXX: pdata <= { ~P_B, ~P_A, ~P_RIGHT, ~P_LEFT, ~P_DOWN, ~P_UP};
```

This SMS mapping uses `P_A` and `P_B`, which causes the observed A/B behavior for MiSTer-mapped controllers.

---

3. **Best practices for the fix**

- Keep the change minimal and localized to SMS-specific mapping.
- Do not alter Mega Drive mode mappings (to avoid regressions in normal Genesis/MD games).
- Match existing hardware/SNAC behavior for consistency.
- Preserve existing style and structure (single-line case update).

---

4. **How to fix**

Update the SMS mapping in `pad_io.sv` to use **B/C** instead of **A/B**.  
Concretely, replace `{~P_B, ~P_A, ...}` with `{~P_C, ~P_B, ...}` in the SMS case.

This aligns MiSTer-mapped controllers with expected SMS behavior.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
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