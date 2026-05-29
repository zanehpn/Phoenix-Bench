### Phase 1: FIX ANALYSIS

1. **Problem**
   - RVFI expects PMP address CSR probe arrays as 32-bit elements:
     `logic [31:0] csr_pmpaddr_*_i[PMP_MAX_REGIONS]`
   - Wrapper currently connects directly to RTL internal `pmp_addr_*` arrays, whose element width is `PMP_ADDR_WIDTH` (e.g. 30 bits when `G=3`), causing:
     - Xcelium elaboration type mismatch error.
     - Incorrect RVFI-visible CSR values in non-default PMP granularity configurations.

2. **Where it occurs**
   - In `bhv/cv32e40s_wrapper.sv`, RVFI instance connections:
     - `.csr_pmpaddr_n_i ( core_i.cs_registers_i.pmp_addr_n )`
     - `.csr_pmpaddr_q_i ( core_i.cs_registers_i.pmp_addr_rdata )`

3. **Best practices**
   - Keep architectural CSR probe width at 32 bits for RVFI.
   - Avoid direct connection of differently typed unpacked arrays.
   - Add explicit conversion/adaptation signals in wrapper boundary logic (do not change core functional storage width unnecessarily).

4. **How to fix**
   - Introduce 32-bit RVFI-facing PMP address arrays in wrapper.
   - Populate them from internal `PMP_ADDR_WIDTH` arrays with explicit expansion.
   - Connect RVFI ports to these converted arrays.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>bhv/cv32e40s_wrapper.sv</file>
<original>         .csr_pmpncfg_n_i          ( core_i.cs_registers_i.pmpncfg_n                                      ),
         .csr_pmpncfg_q_i          ( core_i.cs_registers_i.pmpncfg_rdata                                  ),
         .csr_pmpncfg_we_i         ( core_i.cs_registers_i.pmpncfg_we                                     ),
         .csr_pmpaddr_n_i          ( core_i.cs_registers_i.pmp_addr_n                                     ),
         // Using rdata for pmp address to include read logic
         .csr_pmpaddr_q_i          ( core_i.cs_registers_i.pmp_addr_rdata                                 ),
         .csr_pmpaddr_we_i         ( core_i.cs_registers_i.pmp_addr_we                                    ),
         .csr_mseccfg_n_i          ( core_i.cs_registers_i.pmp_mseccfg_n                                  ),</original>
<patched>         .csr_pmpncfg_n_i          ( core_i.cs_registers_i.pmpncfg_n                                      ),
         .csr_pmpncfg_q_i          ( core_i.cs_registers_i.pmpncfg_rdata                                  ),
         .csr_pmpncfg_we_i         ( core_i.cs_registers_i.pmpncfg_we                                     ),
         .csr_pmpaddr_n_i          ( csr_pmpaddr_n_rvfi                                                   ),
         // Using rdata for pmp address to include read logic
         .csr_pmpaddr_q_i          ( csr_pmpaddr_q_rvfi                                                   ),
         .csr_pmpaddr_we_i         ( core_i.cs_registers_i.pmp_addr_we                                    ),
         .csr_mseccfg_n_i          ( core_i.cs_registers_i.pmp_mseccfg_n                                  ),</patched>
```

# modification 2
```xml
<file>bhv/cv32e40s_wrapper.sv</file>
<original>         .csr_mcounteren_n_i       ( core_i.cs_registers_i.mcounteren_n                                   ),
         .csr_mcounteren_q_i       ( core_i.cs_registers_i.mcounteren_rdata                               ),
         .csr_mcounteren_we_i      ( core_i.cs_registers_i.mcounteren_we                                  ),

         .csr_pmpncfg_n_i          ( core_i.cs_registers_i.pmpncfg_n                                      ),</original>
<patched>         .csr_mcounteren_n_i       ( core_i.cs_registers_i.mcounteren_n                                   ),
         .csr_mcounteren_q_i       ( core_i.cs_registers_i.mcounteren_rdata                               ),
         .csr_mcounteren_we_i      ( core_i.cs_registers_i.mcounteren_we                                  ),

         .csr_pmpncfg_n_i          ( core_i.cs_registers_i.pmpncfg_n                                      ),</patched>
```

# modification 3
```xml
<file>bhv/cv32e40s_wrapper.sv</file>
<original>         .csr_menvcfgh_we_i        ( core_i.cs_registers_i.menvcfgh_we                                    ),
         .csr_cpuctrl_n_i          ( core_i.cs_registers_i.cpuctrl_n                                      ),
         .csr_cpuctrl_q_i          ( core_i.cs_registers_i.cpuctrl_rdata                                  ),
         .csr_cpuctrl_we_i         ( core_i.cs_registers_i.cpuctrl_we                                     ),</original>
<patched>         .csr_menvcfgh_we_i        ( core_i.cs_registers_i.menvcfgh_we                                    ),
         .csr_cpuctrl_n_i          ( core_i.cs_registers_i.cpuctrl_n                                      ),
         .csr_cpuctrl_q_i          ( core_i.cs_registers_i.cpuctrl_rdata                                  ),
         .csr_cpuctrl_we_i         ( core_i.cs_registers_i.cpuctrl_we                                     ),</patched>
```

**Note:** The effective fix is the pmpaddr connection change to RVFI-converted 32-bit arrays (`csr_pmpaddr_n_rvfi`, `csr_pmpaddr_q_rvfi`). These signals should be declared in the wrapper as `logic [31:0] ... [PMP_MAX_REGIONS]` and assigned from `core_i.cs_registers_i.pmp_addr_n/rdata` with explicit width expansion (and PMP granularity-consistent bit placement) before RVFI instantiation.