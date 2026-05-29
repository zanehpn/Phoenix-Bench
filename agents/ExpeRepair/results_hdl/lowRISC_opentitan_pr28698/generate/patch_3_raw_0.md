## Phase 1: FIX ANALYSIS

### 1. What the problem is
The OTBN coverage collection fails for several tests when `--cov` is enabled because mnemonic coverpoints in `otbn_env_cov.sv` are defined with **quoted string bins**, but the covergroup `sample()` functions are being passed **unquoted mnemonic strings**.

After commit `e9986ef486`, the mnemonic bin macro was changed to emit quoted bin values to satisfy Verissimo. That made the coverpoint expect values like `"addi"` instead of `addi`. Since the sampled mnemonic values are still unquoted, the simulator treats them as unmatched and records them as illegal/default values, causing coverage errors and failing tests.

### 2. Where the problem occurs
The issue is in:

- `hw/ip/otbn/dv/uvm/env/otbn_env_cov.sv`

Specifically:
- the mnemonic bin macro definition:
  - `DEF_MNEM_BIN(NAME) bins NAME = {`"NAME`"}`
- the covergroups that sample mnemonics using `mnem_str_t mnemonic` and compare against those bins, for example:
  - `enc_ecall_cg`
  - `enc_i_cg`
  - `pairwise_insn_cg`
  - and others using `DEF_MNEM_BINS_EXCEPT_ECALL`

The sampled values are plain mnemonic strings, while the bins are currently created from quoted tokens.

### 3. Best practices to take into account
- **Make the smallest fix possible**: avoid broad refactors if the problem is only with how bins are written.
- **Keep compatibility with Verissimo**: the quote change was likely introduced to satisfy a tool-specific syntax requirement, so don’t blindly revert it unless necessary.
- **Preserve the semantic meaning of sampled values**: the covergroup should match the actual mnemonic string values passed in at runtime.
- **Prefer fixing the bin generation/source of truth**, not the runtime sampling path, unless the latter is required by tool constraints.
- **Avoid touching unrelated environment code** (`otbn_env.sv`) unless there is evidence it affects the mnemonic encoding.

### 4. How to fix the problem
The cleanest fix is to adjust the mnemonic bin macro so the coverpoint bins match the actual string values being sampled.

Concretely, the macro should define bins using the mnemonic string value rather than the quoted macro name token. If Verissimo requires quoted strings in source, then the sampled/defined type should be aligned accordingly; however, from the issue description and the code shown, the real mismatch is that the bins are expecting the wrong textual form. The fix should therefore make the mnemonic bins correspond to the unquoted mnemonic values that are passed to `sample()`.

If Verissimo truly requires the quoted form in this location, then the alternative would be to ensure the sampled values are generated with quotes too, but that would be more invasive and is not necessary if the coverpoint bins can directly use the string literals already stored in the mnemonic variables.

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