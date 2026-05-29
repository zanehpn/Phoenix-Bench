### Phase 1: FIX ANALYSIS

1. **Problem summary**

The RVFI wrapper connects `core_i.cs_registers_i.pmp_addr_rdata` directly to RVFI port `csr_pmpaddr_q_i`.  
When PMP granularity `G != 0`, `pmp_addr_rdata` is narrower (`PMP_ADDR_WIDTH`, e.g. 30 bits for `G=3`) than RVFI’s expected 32-bit CSR element width.  
Xcelium enforces strict type compatibility for unpacked arrays and fails elaboration.

2. **Where it occurs**

In `bhv/cv32e40s_wrapper.sv`, at the RVFI instantiation around:

- `.csr_pmpaddr_q_i ( core_i.cs_registers_i.pmp_addr_rdata )`

This is exactly the incompatible connection reported in the issue.

3. **Best practices for fix**

- Keep RVFI-visible CSR values at architectural width (32-bit for RV32 CSRs).
- Avoid changing core CSR storage width (it is implementation-driven and valid).
- Apply explicit widening at the wrapper boundary to avoid tool-dependent implicit behavior.
- Keep change minimal and localized.

4. **Fix approach**

Explicitly zero-extend each PMP address entry from `pmp_addr_rdata` to 32 bits in the wrapper connection to RVFI.  
This resolves strict type-checking and ensures RVFI observes correct 32-bit CSR values.

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
         // Using rdata for pmp address to include read logic
         .csr_pmpaddr_q_i          ( '{
           32'(core_i.cs_registers_i.pmp_addr_rdata[0]),  32'(core_i.cs_registers_i.pmp_addr_rdata[1]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[2]),  32'(core_i.cs_registers_i.pmp_addr_rdata[3]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[4]),  32'(core_i.cs_registers_i.pmp_addr_rdata[5]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[6]),  32'(core_i.cs_registers_i.pmp_addr_rdata[7]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[8]),  32'(core_i.cs_registers_i.pmp_addr_rdata[9]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[10]), 32'(core_i.cs_registers_i.pmp_addr_rdata[11]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[12]), 32'(core_i.cs_registers_i.pmp_addr_rdata[13]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[14]), 32'(core_i.cs_registers_i.pmp_addr_rdata[15]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[16]), 32'(core_i.cs_registers_i.pmp_addr_rdata[17]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[18]), 32'(core_i.cs_registers_i.pmp_addr_rdata[19]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[20]), 32'(core_i.cs_registers_i.pmp_addr_rdata[21]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[22]), 32'(core_i.cs_registers_i.pmp_addr_rdata[23]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[24]), 32'(core_i.cs_registers_i.pmp_addr_rdata[25]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[26]), 32'(core_i.cs_registers_i.pmp_addr_rdata[27]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[28]), 32'(core_i.cs_registers_i.pmp_addr_rdata[29]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[30]), 32'(core_i.cs_registers_i.pmp_addr_rdata[31]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[32]), 32'(core_i.cs_registers_i.pmp_addr_rdata[33]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[34]), 32'(core_i.cs_registers_i.pmp_addr_rdata[35]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[36]), 32'(core_i.cs_registers_i.pmp_addr_rdata[37]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[38]), 32'(core_i.cs_registers_i.pmp_addr_rdata[39]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[40]), 32'(core_i.cs_registers_i.pmp_addr_rdata[41]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[42]), 32'(core_i.cs_registers_i.pmp_addr_rdata[43]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[44]), 32'(core_i.cs_registers_i.pmp_addr_rdata[45]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[46]), 32'(core_i.cs_registers_i.pmp_addr_rdata[47]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[48]), 32'(core_i.cs_registers_i.pmp_addr_rdata[49]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[50]), 32'(core_i.cs_registers_i.pmp_addr_rdata[51]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[52]), 32'(core_i.cs_registers_i.pmp_addr_rdata[53]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[54]), 32'(core_i.cs_registers_i.pmp_addr_rdata[55]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[56]), 32'(core_i.cs_registers_i.pmp_addr_rdata[57]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[58]), 32'(core_i.cs_registers_i.pmp_addr_rdata[59]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[60]), 32'(core_i.cs_registers_i.pmp_addr_rdata[61]),
           32'(core_i.cs_registers_i.pmp_addr_rdata[62]), 32'(core_i.cs_registers_i.pmp_addr_rdata[63])
         }                                                                      ),
         .csr_pmpaddr_we_i         ( core_i.cs_registers_i.pmp_addr_we                                    ),</patched>
```