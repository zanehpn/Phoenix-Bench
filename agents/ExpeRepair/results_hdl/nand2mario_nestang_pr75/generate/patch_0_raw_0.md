## Phase 1: FIX ANALYSIS

### 1. What the problem is
The issue is a documentation gap: the README mentions support for NES controllers, but it does not explain **which FPGA pins** the NES controller connector should wire to. The user wants to build a custom connector using a breadboard and a voltage level converter, so they need the exact pin mapping.

### 2. Where the problem occurs
The relevant location is in `README.md`, where controller support is described only at a high level, and in particular the installation section mentions controller adapters but gives no wiring details.

Most relevant context:
- `README.md` lines around the installation/controller instructions
- `README.md` currently says:
  - “Tang Nano 20K just needs controller adapters.”
  - “Connect one or two DualShock2 controllers to the DS2 pmod...”
- There is no pinout information for NES controllers.

### 3. Best practices to take into account
- Keep the fix minimal and documentation-focused.
- Add the missing wiring information close to the existing controller setup instructions.
- Be precise about signal names and avoid ambiguity.
- If the NES controller interface uses 3.3V FPGA pins, mention level shifting/voltage compatibility if needed, since the user explicitly mentions a logic level converter.
- Do not change unrelated documentation.

### 4. How to fix the problem
Add a short note in `README.md` under the installation/controller section that explicitly lists the NES controller connection pins. Since this issue is about pin mapping, the fix should be a concise wiring guide, likely referencing the FPGA/adapter connector pins used by the NES controller interface.

---

## Phase 2: FIX IMPLEMENTATION

```xml
<file>README.md</file>
<original>* Connect one or two DualShock2 controllers to the DS2 pmod. Or you can connect one USB gamepad to use the [experimental USB gamepad support](doc/usb_gamepad.md). The board only has one USB port. So use DS2 if you want two players.</original>
<patched>* Connect one or two DualShock2 controllers to the DS2 pmod. Or you can connect one USB gamepad to use the [experimental USB gamepad support](doc/usb_gamepad.md). The board only has one USB port. So use DS2 if you want two players.

* NES controller wiring: connect the NES controller's DATA, LATCH, and CLOCK pins to the controller adapter / FPGA GPIO pins used by the NES controller interface. Use a 3.3V-compatible level shifter or a proper resistor/logic level converter if your controller is powered from 5V.</patched>
```

