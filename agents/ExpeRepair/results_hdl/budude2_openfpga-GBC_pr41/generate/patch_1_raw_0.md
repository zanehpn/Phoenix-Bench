### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue reports that stereo output is reversed (left/right swapped) in both the GB and GBC cores.

2. **Where it occurs**

From the provided context, the likely configuration point is:

- `pkg/gb/Cores/budude2.GB/audio.json`

This file currently only declares the APF audio manifest version and does not explicitly define stereo channel behavior. If the platform default ordering differs from the core’s internal ordering, channels can come out swapped.

3. **Best practices for the fix**

- Keep the change minimal and localized to audio configuration.
- Avoid touching test files or unrelated logic.
- Preserve valid JSON structure.
- Prefer explicit channel behavior over relying on platform defaults.

4. **Fix approach**

Add an explicit stereo channel swap directive in `audio.json` so the runtime applies the correct left/right orientation.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>pkg/gb/Cores/budude2.GB/audio.json</file>
<original>{
  "audio": {
    "magic": "APF_VER_1" 
  }</original>
<patched>{
  "audio": {
    "magic": "APF_VER_1",
    "swap_channels": true
  }</patched>
```

