### Phase 1: FIX ANALYSIS

1. **Problem summary**

The reported bug is that stereo output is reversed (left/right swapped) on both GB and GBC cores.

2. **Where it occurs**

From the provided context, the relevant file is:

- `pkg/gb/Cores/budude2.GB/audio.json`

This file currently contains only the APF magic field and no explicit stereo mapping behavior. If the core/framework default ordering does not match the core’s internal channel ordering, channels can come out swapped.

3. **Best practices for the fix**

- Make a **minimal manifest-level change** instead of touching unrelated logic.
- Keep JSON valid and backward-compatible.
- Explicitly define channel swap behavior so output is deterministic across framework versions.

4. **How to fix**

Add an explicit stereo swap directive in `audio.json` so the framework maps channels correctly (left/right corrected).

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>pkg/gb/Cores/budude2.GB/audio.json</file>
<original>{
  "audio": {
    "magic": "APF_VER_1" 
  }
}</original>
<patched>{
  "audio": {
    "magic": "APF_VER_1",
    "swap_channels": true
  }
}</patched>
```