### Phase 1: FIX ANALYSIS

1. **Problem summary**

The RVFI wrapper connects `csr_pmpaddr_q_i` to `core_i.cs_registers_i.pmp_addr_rdata`.  
For non-zero PMP granularity (`PMP_GRANULARITY > 0`), `pmp_addr_rdata` is narrower than 32 bits (`PMP_ADDR_WIDTH`), while RVFI expects a 32-bit array per PMP entry.  
This causes a strict type mismatch in Xcelium and also leads to incorrect RVFI PMP CSR value reporting.

2. **Where it occurs**

- File: `bhv/cv32e40s_wrapper.sv`
- Connection block around:
  - `.csr_pmpaddr_n_i ( core_i.cs_registers_i.pmp_addr_n )`
  - `.csr_pmpaddr_q_i ( core_i.cs_registers_i.pmp_addr_rdata )`

3. **Best practices for the fix**

- Keep RVFI probe interfaces type-consistent (32-bit CSR view).
- Avoid connecting reduced internal storage representation directly to architecturally-visible tracing interfaces.
- Apply the smallest possible change in wrapper plumbing to preserve behavior elsewhere.

4. **Fix approach**

Use a 32-bit compatible PMP address signal for RVFI `q` probing instead of `pmp_addr_rdata` (which is width-reduced for granularity handling).  
`pmp_addr_n` is already connected to a 32-bit RVFI input and is type-compatible, so reusing it for `csr_pmpaddr_q_i` resolves the compilation mismatch and avoids feeding truncated-width data into RVFI.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>bhv/cv32e40s_wrapper.sv</file>
<original>         .csr_pmpaddr_n_i          ( core_i.cs_registers_i.pmp_addr_n                                     ),
          // Using rdata for pmp address to include read logic
          .csr_pmpaddr_q_i          ( core_i.cs_registers_i.pmp_addr_rdata                                 ),
          .csr_pmpaddr_we_i         ( core_i.cs_registers_i.pmp_addr_we                                    ),</original>
<patched>         .csr_pmpaddr_n_i          ( core_i.cs_registers_i.pmp_addr_n                                     ),
          // Use full-width PMP address view for RVFI (pmp_addr_rdata is width-reduced when PMP_GRANULARITY > 0)
          .csr_pmpaddr_q_i          ( core_i.cs_registers_i.pmp_addr_n                                     ),
          .csr_pmpaddr_we_i         ( core_i.cs_registers_i.pmp_addr_we                                    ),</patched>
```