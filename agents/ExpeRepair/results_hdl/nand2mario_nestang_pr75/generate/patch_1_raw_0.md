## Phase 1: FIX ANALYSIS

### 1. What the problem is
The issue is that the repository mentions NES controller support, but it does not clearly tell users **which FPGA pins / header pins to use** when building a custom NES controller connector. The user specifically asks for the connection pins so they can wire their own connector with a breadboard and a voltage level converter.

### 2. Where the problem occurs
From the provided context, the most relevant place is the project documentation in:

- `README.md` — it mentions controller support in general, but does **not** specify NES controller pin mapping.
- `README.md` installation section — it only says to connect DualShock2 controllers or USB gamepads.
- `verilator/README.md` is unrelated to controller wiring.

So the documentation gap is in `README.md`, likely near the controller/support section or installation notes.

### 3. Best practices to take into account
- **Document hardware pin mappings explicitly** when third parties may build adapters or connectors.
- **Keep the fix minimal**: only add the missing connection details, without changing unrelated content.
- **Avoid ambiguity**: include signal names and, if applicable, power/ground/reference notes.
- **Prefer exact connector/pin labels** from the board documentation if available.
- **Do not invent pinouts** unless they are already established in the project docs or code.

### 4. How to fix the problem
Add a short documentation note in `README.md` explaining the NES controller connector pin mapping used by the project, so users can wire a custom adapter correctly. Since no explicit pin mapping is present in the provided snippets, the safest repo-side fix is to add a note pointing users to the relevant installation/controller documentation if available in the repository, or to state that the project does not currently provide NES controller wiring details in the README and should link to the definitive doc.

Because the issue asks “which pins do they connect to?”, the documentation should be amended where controller support is described, ideally with a concise wiring reference.

---

## Phase 2: FIX IMPLEMENTATION

No code patch can be safely produced from the provided snippets alone because the exact NES controller pin mapping is not present in any of the supplied code locations, and I must not invent hardware pin assignments.

If you want, I can still help by drafting the exact README wording once you provide the authoritative NES controller pinout or the file that contains it.