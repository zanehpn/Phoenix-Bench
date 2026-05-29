### Phase 1: FIX ANALYSIS

1. **What the problem is**

The README’s AXI5/ATOPs description points to the wrong section of the AMBA5 specification.  
It currently says ATOPs are defined in **Section E1.1**, but the issue report indicates that this reference should be **Section E2.1**.

2. **Where the problem occurs**

The problem is in:

- **`README.md`**
- In the **“Atomic Operations”** section
- Specifically in the sentence describing where ATOPs are defined and where compliant masters/slaves must adhere

3. **Best practices to take into account**

- Make the documentation reference accurate and consistent with the intended specification.
- Apply the smallest possible change: only update the incorrect section reference.
- Avoid unrelated wording changes unless necessary.
- Ensure both mentions of the ATOPs section remain consistent.

4. **How to fix the problem**

Update the AMBA5 section reference in `README.md` from **E1.1** to **E2.1** in the Atomic Operations section.

---

### Phase 2: FIX IMPLEMENTATION

```text
<file>README.md</file>
<original>
AXI4+ATOPs means the full AXI4 specification plus atomic operations (ATOPs) as defined in Section E1.1 of the AMBA5 specification. This has the following implications for modules that do not implement ATOPs and systems that include such modules:
</original>
<patched>
AXI4+ATOPs means the full AXI4 specification plus atomic operations (ATOPs) as defined in Section E2.1 of the AMBA5 specification. This has the following implications for modules that do not implement ATOPs and systems that include such modules:
</patched>
```

