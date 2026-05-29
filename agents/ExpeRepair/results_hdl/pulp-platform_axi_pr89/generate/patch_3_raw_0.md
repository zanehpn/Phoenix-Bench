## Phase 1: FIX ANALYSIS

### 1. What the problem is
The issue is a गलत assertion message in `src/axi_lite_to_apb.sv`.

There is an assertion checking that the AXI4-Lite write strobe width matches the APB strobe width, but the fatal error message incorrectly says **"AXI4-Lite and APB address width not equal"**.  
This is misleading because the failing condition is about **strobe width**, not address width.

### 2. Where the problem occurs
The problem is in the parameter checks inside `check_params` in:

- `src/axi_lite_to_apb.sv`

Specifically this assertion:

```systemverilog
strb_width:  assert ($bits(axi_lite_req_i.w.strb ) == $bits(apb_req_o[0].pstrb)) else
  $fatal(1, $sformatf("AXI4-Lite and APB address width not equal"));
```

The assertion itself is correct, but the message is wrong.

### 3. Best practices to take into account
- Keep the fix minimal and targeted.
- Do not alter working logic unless necessary.
- Make assertion messages precise and descriptive so debug output matches the actual failure.
- Preserve consistency with nearby parameter-check messages.

### 4. How to fix the problem
Update the fatal error string for the strobe-width assertion so it correctly mentions **strobe width** instead of **address width**.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/axi_lite_to_apb.sv</file>
<original>
    strb_width:  assert ($bits(axi_lite_req_i.w.strb ) == $bits(apb_req_o[0].pstrb)) else
      $fatal(1, $sformatf("AXI4-Lite and APB address width not equal"));
</original>
<patched>
    strb_width:  assert ($bits(axi_lite_req_i.w.strb ) == $bits(apb_req_o[0].pstrb)) else
      $fatal(1, $sformatf("AXI4-Lite and APB strobe width not equal"));
</patched>
```