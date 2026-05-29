## Phase 1: FIX ANALYSIS

### 1) What the problem is
The VCO example is broken on ICE40 after the clocking rewrite, while still working on ECP5. The issue likely stems from the VCO’s generated wavetable / control LUT being built with a sample-rate assumption that no longer matches the new clocking architecture. Since the bug only appears on ICE40, it smells like the design is using a hardcoded or stale timing constant that is wrong for that target.

### 2) Where the problem occurs
The most suspicious code is in:

- `gateware/cores/util/vco/gen_v_oct_lut.py`

Specifically:
- `volts_to_delta(...)` uses a hardcoded `sample_rate_hz=46875`
- the LUT generation logic relies on that sample rate to compute wavetable step sizes

If the actual sample clock changed to 48 kHz as part of the rewrite, but this generator still assumes 46.875 kHz, then the VCO pitch scaling will be wrong. This is the kind of mismatch that can be “close enough” on one FPGA/clocking path and visibly wrong on another.

`gen_wavetable.py` looks unrelated to timing; it just emits waveform data. The LUT generator is the relevant location.

### 3) Best practices to take into account
- Keep generated synthesis constants aligned with the real system clock.
- Avoid hardcoded timing values unless they are guaranteed to be valid for all targets.
- Prefer making sample-rate assumptions explicit and target-consistent.
- Keep the fix minimal and local to the timing-dependent calculation.

### 4) How to fix the problem
Update the VCO LUT generator so the delta calculations use the correct sample rate for the rewritten architecture, i.e. 48 kHz instead of 46875 Hz.

If the generated LUT is checked into the repository, it should be regenerated using the corrected sample rate. However, from the provided snippets, the actionable bug is in the generator source itself. The minimal fix is to change the default sample rate used by `volts_to_delta(...)` to `48000`.

---

## Phase 2: FIX IMPLEMENTATION

# modification 1
```text
<file>gateware/cores/util/vco/gen_v_oct_lut.py</file>
<original>def volts_to_delta(volts, wavetable_n_samples=256, sample_rate_hz=46875):
    """Index delta (fractional) for wavetable per sample clock)."""
    return (wavetable_n_samples / sample_rate_hz) * volts_to_freq(volts)</original>
<patched>def volts_to_delta(volts, wavetable_n_samples=256, sample_rate_hz=48000):
    """Index delta (fractional) for wavetable per sample clock)."""
    return (wavetable_n_samples / sample_rate_hz) * volts_to_freq(volts)</patched>
```