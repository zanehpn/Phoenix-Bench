### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue reports inconsistent PLRU behavior for `CMO_PREFETCH` when `prefetch_updt_plru == 1`:

- On **prefetch hit**: PLRU is **not updated**.
- On **prefetch miss**: PLRU **is updated** at refill response time.

This is inconsistent for the same operation class (`CMO_PREFETCH`) under the same configuration intent.

2. **Where it happens**

From the provided context:

- In `hpdcache_miss_handler.sv`, PLRU update on refill is explicitly controlled via:
  - `cfg_prefetch_updt_sel_victim_i` and `is_prefetch`  
  (so miss/refill path already supports prefetch PLRU updates).
- In `hpdcache_ctrl.sv`, the normal request path into `hpdcache_memctrl` uses:
  - `.dir_updt_sel_victim_i(st1_req_updt_sel_victim)`

There is no visible explicit prefetch-hit contribution there, which explains why hit path may skip PLRU update for `CMO_PREFETCH`.

3. **Best practices for the fix**

- Keep changes **minimal** and **localized**.
- Avoid changing request classification or broader CMO semantics.
- Preserve existing refill/miss logic.
- Ensure PLRU update trigger on hit is explicit and conditioned on valid prefetch-hit request.

4. **How to fix**

Patch `hpdcache_ctrl.sv` so `dir_updt_sel_victim_i` is asserted not only by existing control logic, but also on **valid `CMO_PREFETCH` hits**.  
This aligns hit behavior with miss/refill behavior and resolves inconsistency.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>rtl/src/hpdcache_ctrl.sv</file>
<original>        .dir_match_set_i               (st0_req_set),
        .dir_match_tag_i               (st1_req.addr_tag),
        .dir_updt_sel_victim_i         (st1_req_updt_sel_victim),
        .dir_hit_way_o                 (st1_dir_hit_way),
        .dir_hit_tag_o                 (st1_dir_hit_tag),
        .dir_hit_wback_o               (st1_dir_hit_wback),
        .dir_hit_dirty_o               (st1_dir_hit_dirty),
        .dir_hit_fetch_o               (st1_dir_hit_fetch),</original>
<patched>        .dir_match_set_i               (st0_req_set),
        .dir_match_tag_i               (st1_req.addr_tag),
        .dir_updt_sel_victim_i         (st1_req_updt_sel_victim |
                                         (st1_req_valid_q & st1_req_is_cmo_prefetch & st1_dir_hit)),
        .dir_hit_way_o                 (st1_dir_hit_way),
        .dir_hit_tag_o                 (st1_dir_hit_tag),
        .dir_hit_wback_o               (st1_dir_hit_wback),
        .dir_hit_dirty_o               (st1_dir_hit_dirty),
        .dir_hit_fetch_o               (st1_dir_hit_fetch),</patched>
```

