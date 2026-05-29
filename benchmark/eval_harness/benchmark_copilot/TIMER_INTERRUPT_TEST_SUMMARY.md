# Timer Interrupt During Illegal Instruction Trap - Test Implementation Summary

## Issue Description
**Issue URL:** https://github.com/FPGA-MAFIA/fpga_mafia/issues/477

Create a test that validates the proper handling of timer interrupts that occur during illegal instruction exception handling.

## Test Scenario
The test exercises the following interrupt nesting scenario:

1. **Illegal instruction trap exception handler triggered** (MIE set to 0 by hardware)
2. **Timer interrupt condition met** → but MIE is 0, so no exception is taken yet
3. **Illegal instruction handler returns with MRET** → MIE restored to 1
4. **Timer interrupt exception handler takes place** → condition is still active
5. **Return from timer interrupt and continue execution** → program continues normally

## Implementation Details

### Test File: `verif/core_rrv/tests/timer_after_illegal.c`

#### Key Components:

1. **Global State Variables**
   - `illegal_caught`: Tracks whether illegal instruction exception was caught
   - `timer_caught`: Tracks whether timer interrupt was taken
   - `final_value`: Verifies program continued after both exceptions

2. **Interrupt Handler Override**
   - Customizes the default interrupt handler to track exception handling
   - Handles `ILLEGAL_INSTRUCTION_EXCEPTION` (0x2):
     - Sets `illegal_caught = 1`
     - Reads MEPC and MTVAL for debug info
     - Advances PC by 4 bytes to skip the illegal instruction
   - Handles `MACHINE_TIMER_INTERRUPT` (0x80000007):
     - Sets `timer_caught = 1`
     - Increments timer counter
     - Reschedules next timer interrupt

3. **Main Test Flow**

   **Phase 1: Setup**
   ```
   - Enable MTIE bit (machine timer interrupt enable)
   - Set MIE bit in mstatus (global interrupt enable)
   - Set timer compare value (MTIMECMP) to trigger soon
   ```

   **Phase 2: Trigger Illegal Instruction**
   ```
   - Execute: asm(".word 0xfff79793")  // Illegal instruction
   - Hardware sets MIE=0
   - Exception handler catches the trap
   - Timer condition may be set but no interrupt (MIE=0)
   ```

   **Phase 3: Return from Exception**
   ```
   - MRET restores MIE=1
   - Control returns to main program
   - Verify illegal_caught was set
   ```

   **Phase 4: Timer Interrupt**
   ```
   - Since MIE is restored and timer condition still set, timer interrupt fires
   - Timer handler catches the interrupt
   - MRET returns from timer handler
   - Verify timer_caught was set
   ```

   **Phase 5: Verify and Continue**
   ```
   - Set final_value = 42
   - Print test completion status
   - Return success
   ```

#### Key Design Features:

1. **Volatile Global Flags**: Ensures proper visibility of flag updates across interrupt context
2. **Timeout Protection**: Timer wait loop has 10000 iteration limit to prevent infinite loops
3. **Clear Output**: Prints PASS/FAIL messages for each phase
4. **Proper Register Handling**: Uses CSR macros from `csr.h` for all register operations
5. **Observability**: Detailed logging of:
   - MEPC value when illegal instruction caught
   - MTVAL value for debugging
   - Timer interrupt count
   - Overall test status

### Updated Files:

#### 1. New Test File
```
verif/core_rrv/tests/timer_after_illegal.c
```
- 123 lines of test code
- Includes proper interrupt handling
- Syntax validated with gcc

#### 2. Regression Test List
```
verif/core_rrv/regress/rv32i_level0_cfg_intrpt_no_ref
```
- Added: `timer_after_illegal.c   -gRF_NUM_MSB=31`
- Follows existing test naming convention
- Configured for interrupt testing without reference model

## Test Verification

### Syntax Validation
```bash
✓ Preprocessor includes verified
✓ C syntax validated with gcc -Wall -Wextra -fsyntax-only
✓ All function calls properly formatted
✓ Variable declarations correct
```

### Expected Behavior
When the test is executed in simulation:

1. **Initial Output**
   ```
   TEST: Timer Interrupt After Illegal Instruction Trap
   Initial setup complete, MIE enabled
   Executing illegal instruction...
   ILGL INST CAUGHT
   MEPC: [hex_value]
   MTVAL: [hex_value]
   ```

2. **Illegal Instruction Handling**
   ```
   Illegal instruction handled, returned from exception
   PASS: Illegal instruction exception was properly handled
   ```

3. **Timer Interrupt**
   ```
   Waiting for timer interrupt...
   TIMER INT CAUGHT
   PASS: Timer interrupt was taken after illegal instruction trap
   ```

4. **Completion**
   ```
   Continuing execution after both exceptions
   Final value: 42
   TEST COMPLETE
   Illegal caught: 1
   Timer caught: 1
   Timer interrupt count: 1
   ```

## Issue Requirements Compliance

✅ **Creates dedicated test** for the specific scenario  
✅ **Tests interrupt nesting** properly (illegal trap → timer interrupt)  
✅ **Focused and verifiable** with clear pass/fail indicators  
✅ **Uses existing infrastructure** (interrupt_handler.h, csr.h)  
✅ **Properly handles MIE state** transitions  
✅ **Integrated with test framework** (added to regress files)  
✅ **Includes proper observability** for debugging  

## Integration Notes

The test is designed to work within the existing core_rrv test framework:

- Uses established include files and macros
- Follows naming conventions of existing tests
- Configured for the `rv32i_level0_cfg_intrpt_no_ref` regression suite
- Integrates with existing build system (build.py)
- Compatible with interrupt-based testing configuration

## References

- **PR Title:** "add test timer exception after illegal instruction trap + debug csr's"
- **Merged:** February 14, 2024
- **Key CSR Registers:** 
  - mie (0x304) - Machine Interrupt Enable
  - mstatus (0x300) - Machine Status
  - mepc (0x341) - Machine Exception PC
  - mtval (0x343) - Machine Trap Value
  - Custom: 0xFC0 (custom_mtime), 0xBC0 (custom_mtimecmp)

