## Phase 1: FIX ANALYSIS

### 1) What the problem is
The VCO example is broken after the clocking rewrite, but only on ICE40. Since it still works on ECP5, this strongly suggests a mismatch in timing assumptions rather than a fundamental functional bug.

The most likely issue is that the wavetable increment LUT was generated for the old sample clock rate (`46875 Hz`), but the rewritten system now uses `48 kHz` “all round”. That small difference is enough to make pitch/tuning slightly off, and on a timing-sensitive ICE40 design it can also push the VCO behavior into a visibly broken state.

### 2) Where the problem occurs
The most relevant code is in:

- `gateware/cores/util/vco/gen_v_oct_lut.py`

Specifically:

- `volts_to_delta()` uses `sample_rate_hz=46875`
- `print_line()` uses `delta = volts_to_delta(volts)`, so the LUT is generated using that stale sample rate

The issue is therefore in the LUT generation for the VCO’s volts-to-delta mapping.

### 3) Best practices to take into account
- Keep generated lookup tables synchronized with the actual hardware clock/sample rate.
- Prefer a single source of truth for timing-related constants.
- Make the LUT generation reflect the system clock architecture currently used by the design.
- Keep the fix minimal: change the sample-rate constant only where the LUT is generated, unless there is evidence the runtime VCO logic also hardcodes the old rate.

### 4) How to fix the problem
Update the LUT generator to use the new 48 kHz sample rate instead of 46875 Hz.

This is a minimal and targeted fix that matches the issue description and avoids unnecessary changes elsewhere.

---

## Phase 2: FIX IMPLEMENTATION

```xml
<file>gateware/cores/util/vco/gen_v_oct_lut.py</file>
<original>def volts_to_delta(volts, wavetable_n_samples=256, sample_rate_hz=46875):
    """Index delta (fractional) for wavetable per sample clock)."""
    return (wavetable_n_samples / sample_rate_hz) * volts_to_freq(volts)</original>
<patched>def volts_to_delta(volts, wavetable_n_samples=256, sample_rate_hz=48000):
    """Index delta (fractional) for wavetable per sample clock)."""
    return (wavetable_n_samples / sample_rate_hz) * volts_to_freq(volts)</patched>
```

