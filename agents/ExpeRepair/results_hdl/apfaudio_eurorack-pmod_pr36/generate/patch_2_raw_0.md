## Phase 1: FIX ANALYSIS

### 1. What the problem is
The VCO example is broken on ICE40 after the clocking rewrite. The issue appears to be timing-related, and the symptoms point to the wavetable/index delta generation being wrong for the new sample rate / clocking assumptions.

The issue note says it still works on ECP5, which strongly suggests the bug is not in the general VCO design logic, but in a generated lookup table or hardcoded sample-rate-dependent constant that is only wrong for ICE40’s actual clock path.

### 2. Where the problem occurs
The most likely problem is in:

- `gateware/cores/util/vco/gen_v_oct_lut.py`

Specifically, this file contains the generation of the voltage-to-frequency / voltage-to-delta LUT used by the VCO. It hardcodes:

```python
sample_rate_hz=46875
```

in `volts_to_delta()`.

That value is likely stale after the clocking rewrite. If the actual sample clock changed to 48 kHz, then the LUT entries generated from this script will be slightly off. Since the VCO depends on these LUT values for pitch accuracy and phase stepping, even a small mismatch can make the example behave incorrectly.

The other candidate file, `gen_wavetable.py`, is just generating a saw-based wavetable and does not appear tied to timing. The issue is much more likely with LUT generation for the new sample clock.

### 3. Best practices to take into account
- Keep generated coefficients consistent with the actual runtime sample rate.
- Avoid hardcoding timing constants when the system clocking architecture may change.
- Make minimal changes that directly address the mismatch.
- Preserve the LUT format and output structure so downstream code remains compatible.

### 4. How to fix the problem
Update the LUT generation in `gen_v_oct_lut.py` so it uses the new 48 kHz sample rate instead of the stale `46875` value.

This is a minimal fix and aligns the generated VCO delta table with the rewritten clocking architecture. Since the issue only manifests on ICE40, this LUT mismatch is the most plausible cause.

---

## Phase 2: FIX IMPLEMENTATION

```patch
<file>gateware/cores/util/vco/gen_v_oct_lut.py</file>
<original>
def volts_to_delta(volts, wavetable_n_samples=256, sample_rate_hz=46875):
    """Index delta (fractional) for wavetable per sample clock)."""
    return (wavetable_n_samples / sample_rate_hz) * volts_to_freq(volts)
</original>
<patched>
def volts_to_delta(volts, wavetable_n_samples=256, sample_rate_hz=48000):
    """Index delta (fractional) for wavetable per sample clock)."""
    return (wavetable_n_samples / sample_rate_hz) * volts_to_freq(volts)
</patched>
```

