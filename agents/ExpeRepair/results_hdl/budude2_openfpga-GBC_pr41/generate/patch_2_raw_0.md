### Phase 1: FIX ANALYSIS

1. **Problem summary**

The GB/GBC cores are outputting stereo channels in reverse (left comes out right, right comes out left), as confirmed by a dedicated stereo test ROM.

2. **Where it occurs**

From the provided context, the relevant configuration is in:

- `pkg/gb/Cores/budude2.GB/audio.json`

This file currently only declares the APF audio descriptor magic and does not explicitly define channel swap behavior. If the core/platform integration expects explicit stereo mapping, this can result in reversed output.

3. **Best practices for the fix**

- Make the smallest possible change.
- Keep backward compatibility with existing audio path.
- Explicitly define channel behavior instead of relying on implicit defaults.
- Keep JSON valid and minimal.

4. **How to fix**

Add an explicit stereo swap directive in `audio.json` so channel mapping is corrected consistently at runtime.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>pkg/gb/Cores/budude2.GB/audio.json</file>
<original>{
  "audio": {
    "magic": "APF_VER_1" 
  }
</original>
<patched>{
  "audio": {
    "magic": "APF_VER_1",
    "swap_left_right": true
  }
</patched>
```