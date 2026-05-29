## Phase 1: FIX ANALYSIS

### 1. What the problem is
The synthesis tool reports errors because `string` typed `localparam`s are not supported in synthesis in this context.

The failing declarations are:
- `localparam string RomCtrlBootRomInitFile = "...";`
- `localparam string OtpCtrlMemInitFile = "...";`

These are intended to hold file paths for boot ROM / OTP initialization, but the `string` type itself is what synthesis rejects.

### 2. Where the problem occurs
The issue is in `hw/carfield_pkg.sv`, in the “Security Island Parameters” section:
- `RomCtrlBootRomInitFile`
- `OtpCtrlMemInitFile`

### 3. Best practices to take into account
- Avoid SystemVerilog `string` parameters/locals in code that must be accepted by synthesis.
- Prefer synthesizable constant representations such as packed byte arrays or untyped string-like macros only if they are not consumed by synthesis.
- Keep the fix minimal and localized to the synthesis-incompatible declarations.
- Preserve the actual initialization file path values.

### 4. How to fix the problem
Replace the `localparam string` declarations with a synthesizable form.  
A minimal fix is to define them as untyped `localparam`s initialized with string literals, which preserves the values while avoiding the explicit `string` type that triggers the synthesis error.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>hw/carfield_pkg.sv</file>
<original>
localparam string RomCtrlBootRomInitFile = "sw/security_island/bootrom/boot_rom.vmem";
localparam string OtpCtrlMemInitFile     = "sw/security_island/otp/otp-img.mem";
</original>
<patched>
localparam RomCtrlBootRomInitFile = "sw/security_island/bootrom/boot_rom.vmem";
localparam OtpCtrlMemInitFile     = "sw/security_island/otp/otp-img.mem";
</patched>
```