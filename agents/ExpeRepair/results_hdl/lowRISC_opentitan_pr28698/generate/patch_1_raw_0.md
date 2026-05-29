## Phase 1: FIX ANALYSIS

### 1) What the problem is
The OTBN DV coverage collection fails for some tests when coverage is enabled because the mnemonic coverpoints are now defined with string literals that include quotes, but the values sampled into those coverpoints are unquoted mnemonic strings.

So:
- coverpoint bins expect `"addi"`-style values
- the `sample(...)` calls pass `addi`-style values
- Verissimo interprets the unquoted sampled string as not matching any bin, and reports it as illegal/default coverage activity

This only shows up with `--cov`, which is why the simulations pass without coverage.

### 2) Where the problem occurs
The issue is in `hw/ip/otbn/dv/uvm/env/otbn_env_cov.sv`, specifically:
- the mnemonic bin macro definition:
  ```systemverilog
  `define DEF_MNEM_BIN(NAME) bins NAME = {`"NAME`"}
  ```
- and the coverpoints that use `DEF_MNEM_BIN`, especially in the mnemonic covergroups such as:
  ```systemverilog
  covergroup enc_i_cg
    with function sample(mnem_str_t mnemonic, ...);
    mnemonic_cp: coverpoint mnemonic {
      `DEF_MNEM_BIN(mnem_addi);
      ...
    }
  endgroup
  ```

The commit mentioned in the issue changed the macro to add quotes for Verissimo compatibility, but that changed the literal values represented in the bins.

### 3) Best practices to take into account
- Keep coverage bin values consistent with the actual sampled type/value representation.
- Avoid using quoted string forms in one place while sampling bare strings elsewhere unless the type system explicitly requires it.
- Minimize changes: the issue is in the bin macro/coverage representation, not in the rest of the OTBN environment or scoreboard plumbing.
- Preserve compatibility with the toolchain while avoiding functional regression in coverage sampling.

### 4) How to fix the problem
The right fix is to make the mnemonic bins match the actual sampled mnemonic values.

That means:
- either stop emitting quoted string-literals in `DEF_MNEM_BIN`, or
- if Verissimo truly requires quoted representation internally, adapt the sampled values or the mnemonic type so that the sampled values are generated in the same quoted form.

Given the issue description and the observed failure mode, the minimal and correct fix is to restore `DEF_MNEM_BIN` so the bins use the unquoted mnemonic identifiers/strings that match what the `sample(...)` methods pass.

This should restore coverage collection for tests like `otbn_smoke`, `otbn_single`, and `otbn_multi_err` without affecting non-coverage simulation behavior.

---

## Phase 2: FIX IMPLEMENTATION

```patch
<file>hw/ip/otbn/dv/uvm/env/otbn_env_cov.sv</file>
<original>`define DEF_MNEM_BIN(NAME) bins NAME = {`"NAME`"}</original>
<patched>`define DEF_MNEM_BIN(NAME) bins NAME = {NAME}</patched>
```