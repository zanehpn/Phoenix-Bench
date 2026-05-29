## Phase 1: FIX ANALYSIS

### 1) What the problem is
The OTBN coverage collectors are defining mnemonic coverpoint bins using **stringized identifiers** like `"mnem_addi"` instead of the actual mnemonic values like `"addi"` or `addi`-typed string literals.

After commit `e9986ef486`, the `DEF_MNEM_BIN` macro was changed to add quotes around the macro argument to satisfy Verissimo. That made the coverpoint bins expect string values that include the extra quoting behavior, while the sampling code still passes the plain mnemonic text. As a result, valid mnemonics are not matched by any bin and get counted as `illegal_bins`, causing coverage collection to fail the tests.

### 2) Where the problem occurs
The issue is in:

- `hw/ip/otbn/dv/uvm/env/otbn_env_cov.sv`
  - `DEF_MNEM_BIN` macro definition
  - covergroups such as:
    - `enc_ecall_cg`
    - `enc_i_cg`
    - `pairwise_insn_cg`
    - other mnemonic-based covergroups that use `mnem_str_t` sampling and `DEF_MNEM_BIN(...)`

The specific mismatch is between:
- **bin values** created by `DEF_MNEM_BIN`
- **sampled mnemonic values** passed into covergroup `sample(...)`

### 3) Best practices to take into account
- Make the fix **minimal** and **localized**.
- Preserve the intent of the Verissimo workaround if possible, but do not let it change the functional meaning of coverpoint bins.
- Keep the covergroup bins aligned with the actual type/value produced by the sampler.
- Avoid broad refactors unless strictly necessary.
- Prefer a fix that restores correct coverage semantics while maintaining compatibility with lint/syntax requirements.

### 4) How to fix the problem
The best fix is to adjust the mnemonic bin macro so it creates bins that match the **actual mnemonic string values** used at sampling time, rather than quoted macro names.

In practice, this means:
- `DEF_MNEM_BIN(NAME)` should expand to a bin containing the string value corresponding to the mnemonic itself, not the macro identifier as a quoted token.
- If Verissimo requires quoting for syntactic reasons, then the quoting must be done in a way that still yields the actual runtime string value, not `"mnem_addi"`-style literal names.

Given the issue report and the observed failure, the simplest and correct fix is to restore the pre-change behavior for mnemonic bin contents so coverage sampling matches valid mnemonic values again.

---

## Phase 2: FIX IMPLEMENTATION

### modification 1
```text
<file>hw/ip/otbn/dv/uvm/env/otbn_env_cov.sv</file>
<original>
`define DEF_MNEM_BIN(NAME) bins NAME = {`"NAME`"}
</original>
<patched>
`define DEF_MNEM_BIN(NAME) bins NAME = {NAME}
</patched>
```