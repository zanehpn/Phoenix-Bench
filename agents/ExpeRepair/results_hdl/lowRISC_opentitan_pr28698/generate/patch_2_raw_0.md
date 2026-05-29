## Phase 1: FIX ANALYSIS

### 1) What the problem is

The OTBN DV coverage code changed the way mnemonic covergroup bins are defined.  
After commit `e9986ef486`, the macro defining mnemonic bins now inserts quotes around the bin name, so a bin like:

- `mnem_addi`

is effectively being matched against a string literal form like:

- `"mnem_addi"`

But the covergroup sample functions are still called with the mnemonic value itself, e.g. `addi` or `bn.add`, not the quoted string `"addi"`.

As a result, coverage sampling treats valid mnemonics as unmatched values, which triggers `illegal_bins other = default;` and causes coverage-enabled simulations to fail.

---

### 2) Where the problem occurs

The issue is in `hw/ip/otbn/dv/uvm/env/otbn_env_cov.sv`.

The key problematic code is:

```systemverilog
`define DEF_MNEM_BIN(NAME) bins NAME = {`"NAME`"}
```

This macro expands to a quoted string based on the macro name, not the actual mnemonic string value used by the sample function.

This affects coverpoints such as:

- `enc_i_cg.mnemonic_cp`
- `pairwise_insn_cg.last_cp`
- `pairwise_insn_cg.cur_cp`
- other mnemonic coverpoints using `DEF_MNEM_BIN`

The sample functions elsewhere in the environment pass mnemonic strings like `addi` rather than `"mnem_addi"`.

---

### 3) Best practices to take into account

- **Keep coverage bin values aligned with sampled values**: coverpoints must compare the same representation that is passed to `sample()`.
- **Make the fix minimal**: avoid changing the sampling pipeline if only the bin definitions are wrong.
- **Preserve Verissimo compatibility**: if quotes were added to satisfy a tool requirement, keep the representation that the tool expects, but ensure it still matches sampled values.
- **Prefer fixing the macro at the source** rather than changing every call site or every sample function.

---

### 4) How to fix the problem

The best fix is to change the mnemonic bin macro so that it bins against the actual string value associated with each mnemonic, not the macro name wrapped in quotes.

In other words, the mnemonic definitions already store the desired string value, so the bin macro should use that value directly rather than stringizing the macro identifier.

This means:

- keep the `DEF_MNEM(...)` definitions as they are
- update `DEF_MNEM_BIN(NAME)` so it refers to the mnemonic value variable/string value, not the literal macro name text

If the quoted form is required by the coverage tool, then the string value used in the bin must still correspond to the sample input. The current quoted macro expansion breaks that correspondence.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>hw/ip/otbn/dv/uvm/env/otbn_env_cov.sv</file>
<original>
`define DEF_MNEM_BIN(NAME) bins NAME = {`"NAME`"}
</original>
<patched>
`define DEF_MNEM_BIN(NAME) bins NAME = {NAME}
</patched>
```

