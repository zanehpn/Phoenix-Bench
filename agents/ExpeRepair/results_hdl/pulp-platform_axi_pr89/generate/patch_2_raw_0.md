Phase 1: FIX ANALYSIS

1. Problem statement  
The assertion message for the `strb_width` check is wrong. The code correctly asserts that the AXI4-Lite write strobe width matches the APB `pstrb` width, but the fatal error string incorrectly says “address width not equal” instead of referring to the strobe width.

2. Where the problem occurs  
In `src/axi_lite_to_apb.sv`, inside the `check_params` initial block, this assertion is incorrect in its failure message:

- Assertion condition: compares `axi_lite_req_i.w.strb` width against `apb_req_o[0].pstrb`
- Bug: the `$fatal` message says `"AXI4-Lite and APB address width not equal"`

This is clearly a copy-paste mistake from the address-width assertion above it.

3. Best practices to take into account  
- Keep the assertion condition unchanged if it is already correct.
- Make the failure message accurately describe the failing condition.
- Make the fix minimal and targeted to avoid unintended behavior changes.
- Preserve the existing style and formatting of the module.

4. How to fix the problem  
Change the `$fatal` message for the `strb_width` assertion so it states that the AXI4-Lite and APB strobe widths are not equal.

---

Phase 2: FIX IMPLEMENTATION

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