### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue reports inconsistent PLRU behavior for `CMO_PREFETCH` when prefetch PLRU update is enabled (`prefetch_updt_plru == 1`):

- On **prefetch hit**: PLRU is **not** updated.
- On **prefetch miss**: PLRU **is** updated later at refill response.

This is inconsistent and can bias replacement behavior.

---

2. **Where it occurs**

From the provided context:

- In `hpdcache_miss_handler.sv`, PLRU/victim update on refill already explicitly handles prefetches through:
  `cfg_prefetch_updt_sel_victim_i`  
  (seen in `refill_updt_sel_victim_o` logic).
- In `hpdcache_ctrl.sv`, the directory PLRU update signal for request-time behavior is forwarded as:
  `.dir_updt_sel_victim_i (st1_req_updt_sel_victim)`  
  with no explicit prefetch-hit contribution visible in this connection.

So prefetch-miss path updates PLRU (via refill), while prefetch-hit path misses PLRU update.

---

3. **Best practices for the fix**

- Keep behavior **config-driven** (only update on prefetch when prefetch-PLRU-update config is enabled).
- Make a **minimal, local** change in control wiring rather than changing larger FSM behavior.
- Avoid changing refill behavior (already correct for miss path).
- Ensure no functional change for non-prefetch requests.

---

4. **How to fix**

Augment the directory update select signal in `hpdcache_ctrl.sv` so that, in addition to the existing control-engine update signal, it also triggers on:

- valid stage-1 request,
- request is `CMO_PREFETCH`,
- prefetch PLRU update config enabled,
- and the request is a cache hit (`|st1_dir_hit_way`).

This makes prefetch-hit behavior consistent with prefetch-miss behavior under the same config.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>rtl/src/hpdcache_ctrl.sv</file>
<original>        .dir_match_i                   (st0_req_cachedir_read),
        .dir_match_set_i               (st0_req_set),
        .dir_match_tag_i               (st1_req.addr_tag),
        .dir_updt_sel_victim_i         (st1_req_updt_sel_victim),
        .dir_hit_way_o                 (st1_dir_hit_way),
        .dir_hit_tag_o                 (st1_dir_hit_tag),
        .dir_hit_wback_o               (st1_dir_hit_wback),
        .dir_hit_dirty_o               (st1_dir_hit_dirty),
        .dir_hit_fetch_o               (st1_dir_hit_fetch),</original>
<patched>        .dir_match_i                   (st0_req_cachedir_read),
        .dir_match_set_i               (st0_req_set),
        .dir_match_tag_i               (st1_req.addr_tag),
        .dir_updt_sel_victim_i         (st1_req_updt_sel_victim |
                                         (st1_req_valid_q &
                                          st1_req_is_cmo_prefetch &
                                          cfg_prefetch_updt_sel_victim_i &
                                          (|st1_dir_hit_way))),
        .dir_hit_way_o                 (st1_dir_hit_way),
        .dir_hit_tag_o                 (st1_dir_hit_tag),
        .dir_hit_wback_o               (st1_dir_hit_wback),
        .dir_hit_dirty_o               (st1_dir_hit_dirty),
        .dir_hit_fetch_o               (st1_dir_hit_fetch),</patched>
```

