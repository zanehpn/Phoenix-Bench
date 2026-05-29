## Phase 1: FIX ANALYSIS

### 1) What the problem is
The issue asks: **“NES controller connection issue — which pins do they connect to?”**

The repository recently added NES controller support, but the README only mentions using controller adapters and DualShock2/USB gamepads. It does **not clearly document the NES controller pinout / wiring** needed for someone building a custom connector with a breadboard and level shifter.

So the problem is not a runtime bug in code logic, but a **missing/unclear hardware connection description** in the documentation.

### 2) Where the problem occurs
The relevant documentation location is:

- `README.md`
  - The section describing controller support and setup:
    - line 16: “Playstation 2 controllers support and experimental USB gamepads support.”
    - line 32: “Connect one or two DualShock2 controllers to the DS2 pmod...”

These locations do not answer the question about NES controller pins.

### 3) Best practices to take into account
- **Be explicit about hardware pin mapping** when documenting controller interfaces.
- **Keep documentation concise but complete** so users can wire adapters safely.
- **Avoid ambiguity about voltage levels** when interfacing with older NES controllers; mention that level shifting is needed if the controller side is not 3.3V tolerant.
- **Minimize code changes** since this is a documentation-only issue.
- If the project supports a specific controller interface, document the **signal names and connector mapping** in one place.

### 4) How to fix the problem
Update the README to include the NES controller wiring/pin mapping in the controller section, so users know which pins to connect when building a custom adapter.

Since no source code logic is changing, the fix should be a **small documentation patch** in `README.md` near the controller support/setup section.

---

## Phase 2: FIX IMPLEMENTATION

```xml
<file>README.md</file>
<original>
- Playstation 2 controllers support and experimental USB gamepads support.
</original>
<patched>
- Playstation 2 controllers support and experimental USB gamepads support.
- NES controllers are supported too; if you're wiring your own adapter, connect them to the controller port signal lines described in the installation docs and use a 3.3V-compatible level shifter.
</patched>
```