## Phase 1: FIX ANALYSIS

### 1. Problem summary
The synthesis tool reports errors because `string` typed parameters are not supported in synthesis for this codebase/toolchain.

The offending lines define:
- `RomCtrlBootRomInitFile`
- `OtpCtrlMemInitFile`

as `localparam string`, which is legal SystemVerilog for simulation/configuration, but not accepted by the synthesis flow being used.

### 2. Where the problem occurs
The issue is in:

- `hw/carfield_pkg.sv`

Specifically in the “Security Island Parameters” section:

```systemverilog
localparam string RomCtrlBootRomInitFile = "sw/security_island/bootrom/boot_rom.vmem";
localparam string OtpCtrlMemInitFile     = "sw/security_island/otp/otp-img.mem";
```

### 3. Best practices to consider
- Avoid synthesis-unsupported types such as `string` in package parameters/constants that are included in synthesis.
- Prefer using synthesis-friendly types such as `int`, `logic`, or plain compile-time constants.
- If the values are only used for simulation/testbench or non-synthesized configuration, isolate them from synthesis-visible code with synthesis guards.
- Keep the fix minimal and targeted to preserve behavior elsewhere.

### 4. How to fix it
The simplest and most robust fix is to prevent these `string` localparams from being compiled during synthesis, while preserving them for simulation and other non-synthesis flows.

That can be done by wrapping those declarations with synthesis guards such as:

```systemverilog
`ifndef SYNTHESIS
  ...
`endif
```

This way:
- synthesis no longer sees unsupported `string` declarations,
- simulation retains the boot ROM and OTP image path constants.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>hw/carfield_pkg.sv</file>
<original>
/******************************/
/* Security Island Parameters */
/******************************/
localparam string RomCtrlBootRomInitFile = "sw/security_island/bootrom/boot_rom.vmem";
localparam string OtpCtrlMemInitFile     = "sw/security_island/otp/otp-img.mem";
</original>
<patched>
/******************************/
/* Security Island Parameters */
/******************************/
`ifndef SYNTHESIS
localparam string RomCtrlBootRomInitFile = "sw/security_island/bootrom/boot_rom.vmem";
localparam string OtpCtrlMemInitFile     = "sw/security_island/otp/otp-img.mem";
`endif
</patched>
```