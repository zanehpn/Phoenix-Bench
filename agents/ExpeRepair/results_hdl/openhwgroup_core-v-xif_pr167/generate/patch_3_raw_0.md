### Phase 1: FIX ANALYSIS

1. **Problem statement**

The issue is not a functional RTL bug; it is a **spec/interface clarity issue**.  
In `core_v_xif.sv`, parameters `X_MISA` and `X_ECS_XS` are present but their comments are too short to explain their intended role, especially compared to other parameters that are self-explanatory through use in signals/types.

2. **Where the problem occurs**

The ambiguity is in `src/core_v_xif.sv`, in the interface parameter list:

- `parameter logic [31:0] X_MISA = '0`
- `parameter logic [ 1:0] X_ECS_XS = '0`

Both currently have minimal comments and are not directly “used” in struct typedefs/signals, which can make readers think they are stray/unused parameters.

3. **Best practices for the fix**

- Keep the change **minimal** and **non-functional** (documentation-only).
- Clarify purpose in-place where users first see these parameters (parameter declaration comments).
- Explicitly state these are **capability/reset-value descriptors**, not interface transaction payload signals.
- Avoid changing behavior, widths, names, or defaults.

4. **How to fix**

Update the inline comments for `X_MISA` and `X_ECS_XS` to clearly explain:
- what each parameter represents,
- why it exists even though it does not appear in channel structs,
- and how integrators should interpret it.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/core_v_xif.sv</file>
<original>  parameter int unsigned X_NUM_RS               = 2,  // Number of register file read ports that can be used by the eXtension interface
  parameter int unsigned X_ID_WIDTH             = 4,  // Width of ID field.
  parameter int unsigned X_RFR_WIDTH            = 32, // Register file read access width for the eXtension interface
  parameter int unsigned X_RFW_WIDTH            = 32, // Register file write access width for the eXtension interface
  parameter int unsigned X_NUM_HARTS            = 1,  // Number of harts (hardware threads) associated with the interface
  parameter int unsigned X_HARTID_WIDTH         = 1,  // Width of ``hartid`` signals.
  parameter logic [31:0] X_MISA                 = '0, // MISA extensions implemented on the eXtension interface
  parameter logic [ 1:0] X_ECS_XS               = '0, // Initial value for mstatus.XS
  parameter int unsigned X_DUALREAD             = 0,  // Is dual read supported? 0: No, 1: Yes, for ``rs1``, 2: Yes, for ``rs1`` - ``rs2``, 3: Yes, for ``rs1`` - ``rs3``
  parameter int unsigned X_DUALWRITE            = 0,  // Is dual write supported? 0: No, 1: Yes.
  parameter int unsigned X_ISSUE_REGISTER_SPLIT = 0,  // Does the interface pipeline register interface? 0: No, 1: Yes.
  parameter int unsigned X_MEM_WIDTH            = 32  // Memory access width for loads/stores via the eXtension interface</original>
<patched>  parameter int unsigned X_NUM_RS               = 2,  // Number of register file read ports that can be used by the eXtension interface
  parameter int unsigned X_ID_WIDTH             = 4,  // Width of ID field.
  parameter int unsigned X_RFR_WIDTH            = 32, // Register file read access width for the eXtension interface
  parameter int unsigned X_RFW_WIDTH            = 32, // Register file write access width for the eXtension interface
  parameter int unsigned X_NUM_HARTS            = 1,  // Number of harts (hardware threads) associated with the interface
  parameter int unsigned X_HARTID_WIDTH         = 1,  // Width of ``hartid`` signals.
  parameter logic [31:0] X_MISA                 = '0, // ``misa`` extension-bit mask implemented via this interface (capability declaration; not transported on CV-X-IF channels)
  parameter logic [ 1:0] X_ECS_XS               = '0, // Reset/initial value of ``mstatus.XS`` associated with the extension context (integration/CSR initialization parameter)
  parameter int unsigned X_DUALREAD             = 0,  // Is dual read supported? 0: No, 1: Yes, for ``rs1``, 2: Yes, for ``rs1`` - ``rs2``, 3: Yes, for ``rs1`` - ``rs3``
  parameter int unsigned X_DUALWRITE            = 0,  // Is dual write supported? 0: No, 1: Yes.
  parameter int unsigned X_ISSUE_REGISTER_SPLIT = 0,  // Does the interface pipeline register interface? 0: No, 1: Yes.
  parameter int unsigned X_MEM_WIDTH            = 32  // Memory access width for loads/stores via the eXtension interface</patched>
```