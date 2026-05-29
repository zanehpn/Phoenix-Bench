### Phase 1: FIX ANALYSIS

1. **Problem summary**

The RVFI probe port `csr_pmpaddr_q_i` expects an unpacked array of **32-bit** entries:
- `input logic [31:0] csr_pmpaddr_q_i[PMP_MAX_REGIONS]`

But the wrapper currently connects it directly to:
- `core_i.cs_registers_i.pmp_addr_rdata`

which is an unpacked array of **`PMP_ADDR_WIDTH`** entries (e.g. 30 bits when `PMP_GRANULARITY=3`).  
This causes strict type mismatch in Xcelium and also leads to incorrect RVFI CSR visibility for PMP address values.

2. **Where it occurs**

In `bhv/cv32e40s_wrapper.sv`, the problematic connection is here:

- `.csr_pmpaddr_q_i ( core_i.cs_registers_i.pmp_addr_rdata )`

(from provided Location #1)

3. **Best practices for the fix**

- Keep RTL behavior unchanged; only adapt probe wiring.
- Avoid broad refactors; apply minimal targeted conversion at connection point.
- Make conversion explicit so strict simulators (Xcelium) accept it.
- Preserve array structure and index mapping 1:1.

4. **Fix approach**

Explicitly build a 32-bit unpacked array assignment pattern in the wrapper connection, casting each PMP entry to 32 bits.  
This resolves type compatibility and ensures RVFI receives 32-bit CSR data elements.

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
         .csr_pmpaddr_n_i          ( core_i.cs_registers_i.pmp_addr_n                                     ),
         // Using rdata for pmp address to include read logic
         .csr_pmpaddr_q_i          ( '{
                                      0:  32'(core_i.cs_registers_i.pmp_addr_rdata[0]),
                                      1:  32'(core_i.cs_registers_i.pmp_addr_rdata[1]),
                                      2:  32'(core_i.cs_registers_i.pmp_addr_rdata[2]),
                                      3:  32'(core_i.cs_registers_i.pmp_addr_rdata[3]),
                                      4:  32'(core_i.cs_registers_i.pmp_addr_rdata[4]),
                                      5:  32'(core_i.cs_registers_i.pmp_addr_rdata[5]),
                                      6:  32'(core_i.cs_registers_i.pmp_addr_rdata[6]),
                                      7:  32'(core_i.cs_registers_i.pmp_addr_rdata[7]),
                                      8:  32'(core_i.cs_registers_i.pmp_addr_rdata[8]),
                                      9:  32'(core_i.cs_registers_i.pmp_addr_rdata[9]),
                                      10: 32'(core_i.cs_registers_i.pmp_addr_rdata[10]),
                                      11: 32'(core_i.cs_registers_i.pmp_addr_rdata[11]),
                                      12: 32'(core_i.cs_registers_i.pmp_addr_rdata[12]),
                                      13: 32'(core_i.cs_registers_i.pmp_addr_rdata[13]),
                                      14: 32'(core_i.cs_registers_i.pmp_addr_rdata[14]),
                                      15: 32'(core_i.cs_registers_i.pmp_addr_rdata[15]),
                                      16: 32'(core_i.cs_registers_i.pmp_addr_rdata[16]),
                                      17: 32'(core_i.cs_registers_i.pmp_addr_rdata[17]),
                                      18: 32'(core_i.cs_registers_i.pmp_addr_rdata[18]),
                                      19: 32'(core_i.cs_registers_i.pmp_addr_rdata[19]),
                                      20: 32'(core_i.cs_registers_i.pmp_addr_rdata[20]),
                                      21: 32'(core_i.cs_registers_i.pmp_addr_rdata[21]),
                                      22: 32'(core_i.cs_registers_i.pmp_addr_rdata[22]),
                                      23: 32'(core_i.cs_registers_i.pmp_addr_rdata[23]),
                                      24: 32'(core_i.cs_registers_i.pmp_addr_rdata[24]),
                                      25: 32'(core_i.cs_registers_i.pmp_addr_rdata[25]),
                                      26: 32'(core_i.cs_registers_i.pmp_addr_rdata[26]),
                                      27: 32'(core_i.cs_registers_i.pmp_addr_rdata[27]),
                                      28: 32'(core_i.cs_registers_i.pmp_addr_rdata[28]),
                                      29: 32'(core_i.cs_registers_i.pmp_addr_rdata[29]),
                                      30: 32'(core_i.cs_registers_i.pmp_addr_rdata[30]),
                                      31: 32'(core_i.cs_registers_i.pmp_addr_rdata[31]),
                                      32: 32'(core_i.cs_registers_i.pmp_addr_rdata[32]),
                                      33: 32'(core_i.cs_registers_i.pmp_addr_rdata[33]),
                                      34: 32'(core_i.cs_registers_i.pmp_addr_rdata[34]),
                                      35: 32'(core_i.cs_registers_i.pmp_addr_rdata[35]),
                                      36: 32'(core_i.cs_registers_i.pmp_addr_rdata[36]),
                                      37: 32'(core_i.cs_registers_i.pmp_addr_rdata[37]),
                                      38: 32'(core_i.cs_registers_i.pmp_addr_rdata[38]),
                                      39: 32'(core_i.cs_registers_i.pmp_addr_rdata[39]),
                                      40: 32'(core_i.cs_registers_i.pmp_addr_rdata[40]),
                                      41: 32'(core_i.cs_registers_i.pmp_addr_rdata[41]),
                                      42: 32'(core_i.cs_registers_i.pmp_addr_rdata[42]),
                                      43: 32'(core_i.cs_registers_i.pmp_addr_rdata[43]),
                                      44: 32'(core_i.cs_registers_i.pmp_addr_rdata[44]),
                                      45: 32'(core_i.cs_registers_i.pmp_addr_rdata[45]),
                                      46: 32'(core_i.cs_registers_i.pmp_addr_rdata[46]),
                                      47: 32'(core_i.cs_registers_i.pmp_addr_rdata[47]),
                                      48: 32'(core_i.cs_registers_i.pmp_addr_rdata[48]),
                                      49: 32'(core_i.cs_registers_i.pmp_addr_rdata[49]),
                                      50: 32'(core_i.cs_registers_i.pmp_addr_rdata[50]),
                                      51: 32'(core_i.cs_registers_i.pmp_addr_rdata[51]),
                                      52: 32'(core_i.cs_registers_i.pmp_addr_rdata[52]),
                                      53: 32'(core_i.cs_registers_i.pmp_addr_rdata[53]),
                                      54: 32'(core_i.cs_registers_i.pmp_addr_rdata[54]),
                                      55: 32'(core_i.cs_registers_i.pmp_addr_rdata[55]),
                                      56: 32'(core_i.cs_registers_i.pmp_addr_rdata[56]),
                                      57: 32'(core_i.cs_registers_i.pmp_addr_rdata[57]),
                                      58: 32'(core_i.cs_registers_i.pmp_addr_rdata[58]),
                                      59: 32'(core_i.cs_registers_i.pmp_addr_rdata[59]),
                                      60: 32'(core_i.cs_registers_i.pmp_addr_rdata[60]),
                                      61: 32'(core_i.cs_registers_i.pmp_addr_rdata[61]),
                                      62: 32'(core_i.cs_registers_i.pmp_addr_rdata[62]),
                                      63: 32'(core_i.cs_registers_i.pmp_addr_rdata[63])
                                    }                                                                         ),
         .csr_pmpaddr_we_i         ( core_i.cs_registers_i.pmp_addr_we                                    ),
         .csr_mseccfg_n_i          ( core_i.cs_registers_i.pmp_mseccfg_n                                  ),</patched>
```