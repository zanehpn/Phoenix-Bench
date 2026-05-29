# Benchmark Case: AsFigo PySlint PR#166 - VLT: No Clocking Blocks in Interface

## Status: ✅ COMPLETE & VERIFIED

**Issue**: VLT: no clocking blocks in interface  
**PR Number**: #166  
**Benchmark Case**: `AsFigo_pyslint_pr166`  
**Task**: Add a VLT (Verilator) rule to detect clocking blocks in interfaces and flag them as incompatible  
**Location**: `/workspace/phoenix-bench/HDL_agent_eval/benchmark_3/snapshots/AsFigo_pyslint_pr166`

---

## Implementation Summary

A complete VLT rule (`VLT_NO_CLK_BLK_IN_INTF`) has been implemented to detect SystemVerilog clocking blocks within interfaces and flag them as incompatible with Verilator's capabilities.

### Rule Overview
- **Rule ID**: `VLT_NO_CLK_BLK_IN_INTF`
- **Purpose**: Detect clocking block declarations inside interface blocks
- **Severity**: Violation (incompatible with Verilator)
- **Message**: "A clocking block was found inside an interface. Verilator does not support clocking block based driving: [code snippet]"

---

## Implementation Details

### 1. Rule Registration (Line 21)
```python
lv_sv_ruleid_l.append('VLT_NO_CLK_BLK_IN_INTF')
```
- Registered in `pyslint_update_rule_ids()` function
- Added to the complete list of PySlint rule IDs

### 2. Rule Implementation (Lines 117-125)
```python
def VLT_NO_CLK_BLK_IN_INTF(lv_cu_scope):
  if (lv_cu_scope.kind.name == 'InterfaceDeclaration'):
    for lv_intf_mem_i in lv_cu_scope.members:
      if (lv_intf_mem_i.kind.name == 'ClockingDeclaration'):
        msg = 'A clocking block was found inside an interface. '
        msg += 'Verilator does not support clocking block based driving: '
        msg += str(lv_intf_mem_i)
        lv_rule_id = 'VLT_NO_CLK_BLK_IN_INTF'
        pyslint_msg(lv_rule_id, msg)
```

**Algorithm**:
1. Check if scope is an `InterfaceDeclaration`
2. Iterate through all members of the interface
3. Check if any member is a `ClockingDeclaration`
4. Report violation with code snippet if found

### 3. Rule Invocation (Line 1055)
```python
VLT_NO_CLK_BLK_IN_INTF(scope_i)
```
- Called in the main rule processing loop
- Executes for each compilation unit scope

---

## Test Case

### File: `sv_tests/test_issue_165_f.sv`

```systemverilog
interface af_if;
  logic clk;
  logic req;

  clocking cb @(posedge clk);
    output req;
  endclocking
endinterface : af_if
```

**Expected Output**:
```
PySlint: Violation: [VLT_NO_CLK_BLK_IN_INTF]: A clocking block was found inside an interface. 
Verilator does not support clocking block based driving: 
  clocking cb @(posedge clk);
    output req;
  endclocking
```

### Test Execution
```bash
$ cd exec_dir
$ python3 ../py_src/pyslint.py -t ../sv_tests/test_issue_165_f.sv
```

**Result**: ✅ PASS - Rule correctly detects clocking block and reports violation

---

## Files Modified

### File: `py_src/pyslint.py` (1087 lines)
- **Modification Type**: Enhancement (Rule Implementation)
- **Lines Added**: 9 (Rule implementation)
- **Status**: ✅ Complete and tested

**Changes**:
1. Rule ID registered in `pyslint_update_rule_ids()` (Line 21)
2. Rule function implementation (Lines 117-125)
3. Rule invocation in main loop (Line 1055)

### File: `sv_tests/test_issue_165_f.sv` (9 lines)
- **Status**: ✅ Test case exists and validates rule
- **Purpose**: Demonstrates clocking block inside interface

---

## Validation Results

### ✅ Rule Detection
- Correctly identifies ClockingDeclaration nodes within InterfaceDeclaration
- Properly iterates through interface members
- Reports violations with appropriate error message and code snippet

### ✅ Integration
- Rule registered in rule list
- Rule function called in main processing loop
- Uses standard error reporting function (`pyslint_msg`)
- Follows existing PySlint patterns

### ✅ Test Execution
- Full test suite execution: ✅ PASS
- Specific issue 165 test: ✅ PASS
- Rule properly reports violation for test case
- No false positives on other test files

---

## Pattern Compliance

The implementation follows existing PySlint patterns:

### Pattern 1: Rule Registration
```python
# Consistent with other VLT rules (VLT_NO_GENERIC_MBX)
lv_sv_ruleid_l.append('VLT_NO_CLK_BLK_IN_INTF')
```

### Pattern 2: Rule Implementation
```python
# Standard pattern: Check scope type → Iterate members → Check condition → Report
def VLT_NO_CLK_BLK_IN_INTF(lv_cu_scope):
  if (lv_cu_scope.kind.name == 'InterfaceDeclaration'):
    for lv_intf_mem_i in lv_cu_scope.members:
      if (lv_intf_mem_i.kind.name == 'ClockingDeclaration'):
        # ... report violation
```

### Pattern 3: Error Reporting
```python
# Uses standard error reporting function
pyslint_msg(lv_rule_id, msg)
```

### Pattern 4: Rule Invocation
```python
# Called in main rule processing loop alongside other rules
VLT_NO_CLK_BLK_IN_INTF(scope_i)
```

---

## Technical Specifications

### Rule Behavior
- **Scope**: Interfaces only
- **Detection**: ClockingDeclaration AST nodes within InterfaceDeclaration
- **Report Type**: Violation (incompatibility flagged)
- **Message Format**: "A clocking block was found inside an interface. Verilator does not support clocking block based driving: [code]"

### AST Node Types
- **Container**: `InterfaceDeclaration` (lv_cu_scope)
- **Member Type**: `ClockingDeclaration` (lv_intf_mem_i)

### Error Handling
- Gracefully handles interfaces without clocking blocks (no error)
- Only reports when clocking block is found
- Uses standard PySlint error reporting

---

## Summary

✅ **Complete Implementation** of VLT_NO_CLK_BLK_IN_INTF rule:
- Detects clocking blocks in interfaces
- Flags them as incompatible with Verilator
- Properly integrated into PySlint framework
- Follows existing code patterns
- Fully tested with dedicated test case
- All project checks pass

The implementation is surgical, focused, and follows the established PySlint patterns for Verilator compatibility rules.

