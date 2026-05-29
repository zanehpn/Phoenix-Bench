## Phase 1: FIX ANALYSIS

### 1) What the problem is
The README section about AXI5 atomic operations points to the wrong AMBA5 specification section.

It currently says ATOPs are defined in **Section E1.1**, but the issue report indicates the README should point to **Section E2.1** instead.

### 2) Where the problem occurs
The problem is in:

- `README.md`
- the **Atomic Operations** section
- specifically the sentence describing where ATOPs are defined

Relevant text:
> `AXI4+ATOPs means the full AXI4 specification plus atomic operations (ATOPs) as defined in Section E1.1 of the AMBA5 specification.`

and also:
> `Masters and slaves that do support ATOPs must adhere to Section E1.1 of the AMBA5 specification.`

### 3) Best practices to take into account
- Make the smallest possible change.
- Only update the incorrect specification reference.
- Keep wording consistent across the README so the same concept refers to the same section throughout.
- Avoid unrelated edits.

### 4) How to fix the problem
Update the AXI5/ATOPs section references in `README.md` from **E1.1** to **E2.1** in the Atomic Operations section.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>README.md</file>
<original>
AXI4+ATOPs means the full AXI4 specification plus atomic operations (ATOPs) as defined in Section E1.1 of the AMBA5 specification. This has the following implications for modules that do not implement ATOPs and systems that include such modules:
</original>
<patched>
AXI4+ATOPs means the full AXI4 specification plus atomic operations (ATOPs) as defined in Section E2.1 of the AMBA5 specification. This has the following implications for modules that do not implement ATOPs and systems that include such modules:
</patched>
```

```text
<file>README.md</file>
<original>
Masters and slaves that do support ATOPs must adhere to Section E1.1 of the AMBA5 specification.
</original>
<patched>
Masters and slaves that do support ATOPs must adhere to Section E2.1 of the AMBA5 specification.
</patched>
```
