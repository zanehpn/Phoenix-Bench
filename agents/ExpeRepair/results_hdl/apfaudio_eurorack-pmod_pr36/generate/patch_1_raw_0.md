## Phase 1: FIX ANALYSIS

### 1) What the problem is
The VCO example is broken after the clocking rewrite, but only on ICE40 hardware. The symptom strongly suggests a sample-rate / timing mismatch rather than an algorithmic issue in the oscillator itself.

The key clue is that the example still works on ECP5, which points to a hardware-specific clocking difference on ICE40. That usually means some part of the VCO lookup-table generation or frequency-to-phase-step conversion is using a hardcoded sample rate that no longer matches the actual runtime sample clock.

### 2) Where the problem occurs
The most suspicious location is:

- `gateware/cores/util/vco/gen_v_oct_lut.py`

Specifically:

- `volts_to_delta(...)`
- `print_line(...)`
- the LUT generation loop at the bottom

The code currently assumes a fixed `sample_rate_hz=46875`, which was likely valid before the clocking rewrite but may no longer match the ICE40 sample clock.

This would cause the VCO’s phase increment table to be generated incorrectly, leading to pitch errors or instability, especially on the platform whose clock changed.

### 3) Best practices to take into account
- Avoid hardcoded timing constants when the system clocking architecture can differ by target platform.
- Keep LUT generation consistent with the actual sample clock used by the gateware.
- Make the fix minimal and targeted: do not alter unrelated wavetable logic or waveform generation unless necessary.
- Preserve compatibility where possible, especially if ECP5 still works.
- Prefer updating the LUT generation source of truth rather than compensating elsewhere.

### 4) How to fix the problem
Update the VCO LUT generation to use the correct sample rate for the ICE40 configuration. Since the issue appeared after a clocking rewrite and only ICE40 is broken, the likely fix is to adjust the default `sample_rate_hz` in `gen_v_oct_lut.py` to match the new ICE40 sample clock.

From the context, `46875` appears to be stale. A more likely post-rewrite sample rate is `48000`, matching the reported “switching to 48kHz all round”.

So the fix is:
- change the default sample rate in `volts_to_delta(...)` from `46875` to `48000`
- no other changes are necessary based on the provided locations

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

