### Phase 1: FIX ANALYSIS

1. **Problem statement**

The issue reports an inconsistency for `CMO_PREFETCH` when `prefetch_updt_plru == 1`:
- on **hit**: PLRU is **not** updated,
- on **miss**: PLRU **is** updated at refill completion.

This is inconsistent replacement-policy behavior for the same operation class.

2. **Where it occurs**

From the provided context:
- `rtl/src/hpdcache_miss_handler.sv` already updates victim selection on refill for prefetches when config allows it:
  - `refill_updt_sel_victim_o = ... (~is_prefetch | cfg_prefetch_updt_sel_victim_i);`
- In `rtl/src/hpdcache_pkg.sv`, `is_cmo()` currently includes `is_cmo_prefetch(op)`.

That classification is likely causing prefetch hits to be treated like “CMO control ops” (fence/flush/inval class), which typically do not update replacement state on hit. Meanwhile, miss/refill path has explicit prefetch-aware PLRU update logic, creating the mismatch observed.

3. **Best practices for fix**

- Keep behavior coherent between hit and miss paths for the same op.
- Avoid broad behavioral changes; apply minimal semantic correction.
- Preserve dedicated `is_cmo_prefetch()` decode for paths that need explicit prefetch handling.
- Keep fence/flush/inval grouped as CMO control ops; treat prefetch as a data-access hint operation.

4. **How to fix**

Make `is_cmo()` exclude `CMO_PREFETCH`, so generic “CMO control-op” handling won’t swallow prefetch into non-PLRU-updating logic on hit paths. Prefetch remains individually decodable via `is_cmo_prefetch()`.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>rtl/src/hpdcache_pkg.sv</file>
<original>    function automatic logic is_cmo(input hpdcache_req_op_t op);
        return (is_cmo_flush(op) ||
                is_cmo_fence(op) ||
                is_cmo_inval(op) ||
                is_cmo_prefetch(op));
    endfunction</original>
<patched>    function automatic logic is_cmo(input hpdcache_req_op_t op);
        // Prefetch is decoded separately through is_cmo_prefetch().
        // Keep is_cmo() for CMO control operations (flush/fence/inval),
        // so prefetch can follow regular data-access replacement behavior.
        return (is_cmo_flush(op) ||
                is_cmo_fence(op) ||
                is_cmo_inval(op));
    endfunction</patched>
```

