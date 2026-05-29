### Phase 1: FIX ANALYSIS

#### 1. What the problem is
The issue is asking where the newly added NES controller support connects on the hardware. The current documentation mentions controller support in general, but it does not clearly specify which pins on the Tang board / controller connector should be used for an NES controller connection. That makes it hard for someone to build a custom connector with a breadboard and a logic-level converter.

#### 2. Where the problem occurs
The relevant problem is in the documentation, specifically:

- `README.md` — it mentions controller support, but does not explain NES controller pin connections.
- The most relevant place to clarify this is the installation / controller section in `README.md`, where hardware connection instructions are given.

No code logic appears broken; this is a documentation gap.

#### 3. Best practices to take into account
- Keep the fix minimal and documentation-focused.
- Provide explicit pin mapping and wiring direction.
- Mention any electrical requirements clearly, especially if a voltage level converter is needed.
- Avoid changing unrelated project content.
- Use concise language so builders can wire the controller correctly without ambiguity.

#### 4. How to fix the problem
Update the README installation/controller instructions to explicitly state the NES controller wiring/pin connections. Since the issue is about hardware connection guidance, the fix should add a short wiring note in `README.md` near the controller instructions.

---

### Phase 2: FIX IMPLEMENTATION

```
<file>README.md</file>
<original>
* Connect one or two DualShock2 controllers to the DS2 pmod. Or you can connect one USB gamepad to use the [experimental USB gamepad support](doc/usb_gamepad.md). The board only has one USB port. So use DS2 if you want two players.
</original>
<patched>
* Connect one or two DualShock2 controllers to the DS2 pmod. Or you can connect one USB gamepad to use the [experimental USB gamepad support](doc/usb_gamepad.md). The board only has one USB port. So use DS2 if you want two players.
* NES controllers use the same controller interface signals: VCC, GND, clock, latch, and data. Wire them through a 3.3V-compatible level shifter, with clock/latch from the FPGA to the controller and data from the controller back to the FPGA.
</patched>
```