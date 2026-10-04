# Drawing 1,000+ enemies in Godot 4.7 2D

Research for issue #2. Question: what are the options for drawing 1,000+ simple 2D enemies at 60 fps, what does each cost, and how does isometric draw order (enemies y-sorted against towers, piles and terrain) work with each?

Sources are the Godot 4.7.2-stable source tree and class reference (`doc/classes/*.xml` at tag `4.7.2-stable`), the official docs, and the Godot blog. Nothing here was benchmarked; costs are read from the engine code, not measured on the baseline M5 MacBook.

## Summary

- The premise "batched drawing ignores node y-sort" is only half true. Since Godot 4.4, the Forward+ and Mobile renderers batch *across separate canvas items after y-sort has ordered them*. Consecutive items that share a texture, material and command type collapse into one draw call. Only MultiMesh (one canvas item drawing many instances) is opaque to y-sort.
- So there are two families:
  1. **One canvas item per enemy** (a `Sprite2D` node, or a raw `RenderingServer` canvas item). Y-sort works for free against towers, piles and terrain. Batching still applies if everything in the y-sorted layer draws textured rects from one atlas texture.
  2. **One MultiMesh for all enemies.** One draw call and the cheapest CPU path, but the whole MultiMesh sorts as a single item, so enemies cannot interleave with towers or piles without extra work.
- Recommendation for v1: **raw `RenderingServer` canvas items, one per enemy, parented under a y-sorted node alongside towers and piles, all drawn as textured rects from one shared atlas.** It keeps correct isometric occlusion with no custom sorting, avoids scene-node overhead, and keeps enemies as plain data as `docs/design.md` requires. Keep MultiMesh in reserve if profiling shows the per-item cost is too high.

## How the 2D pipeline orders and batches

1. **Cull and sort (CPU, `RendererCanvasCull`).** Each frame, for a canvas item with `sort_y` enabled, the server collects all y-sorted descendants into one array and sorts it with `ItemYSort`, which compares the Y of each item's origin (`ysort_xform.columns[2].y`), falling back to child order when equal. Source: `servers/rendering/renderer_canvas_cull.cpp` lines ~438–460, `renderer_canvas_cull.h` lines 117–127. This sort runs every frame, so its cost is O(n log n) in the number of y-sorted items regardless of whether anything moved.
2. **Z index.** Items are bucketed by absolute Z index (`z_list[p_z - CANVAS_ITEM_Z_MIN]`). Y-sort only orders items within the same Z. `CanvasItem.z_index`: "Nodes sort relative to each other only when sharing the same z_index value." ([CanvasItem docs](https://docs.godotengine.org/en/stable/classes/class_canvasitem.html))
3. **Batch (render, `RendererCanvasRenderRD::_render_batch_items`).** Walks the already-sorted item list and starts a new batch when the clip owner, material, lighting, command type or texture changes. Source: `servers/rendering/renderer_rd/renderer_canvas_render_rd.cpp` lines ~2186–2470.
   - `TYPE_RECT` (sprites, `draw_texture_rect`, `draw_rect`) and `TYPE_NINEPATCH` batch.
   - `TYPE_PRIMITIVE` (`draw_primitive`, up to 4 points) batches while the point count stays the same.
   - `TYPE_POLYGON` never batches: "Polygon's can't be batched, so always create a new batch" (line ~2616). This covers `draw_colored_polygon`, `draw_polygon` and `Polygon2D`.
   - `TYPE_MESH`, `TYPE_MULTIMESH`, `TYPE_PARTICLES` never batch with neighbours (line ~2745), but a MultiMesh is already one instanced draw.
   - Up to `rendering/2d/batching/item_buffer_size` (default 16,384) commands fit in one draw call.
4. RD batching shipped in 4.4 (GH-92797). The Compatibility renderer has batched since 4.0. ([Godot 4.4 dev 3 blog post](https://godotengine.org/article/dev-snapshot-godot-4-4-dev-3/)) The blog notes the benefit is largest for "repeated sprites that share a texture (e.g. when using tilemaps or making a bullet hell)".

Consequence for pile-up's "plain coloured shapes" art: a diamond drawn with `draw_colored_polygon` costs one draw call per shape. The same diamond as a small white texture drawn with `draw_texture_rect` and a modulate colour batches. Pile blocks, enemies and tower bases should all be textured rects from one atlas.

## Options

### 1. One scene node per enemy (`Sprite2D` / `Node2D`)

- **Draw cost:** batched, as above, if all sprites share one texture and material.
- **CPU cost:** highest. Every node carries the scene-tree layer: notifications, transform propagation, a `CanvasItem` on the server, plus the server-side canvas item. The official servers page lists the costs of the scene system as "an extra layer of complexity", "performance is lower than when using simple APIs directly" and "more memory is needed". ([Optimization using Servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html))
- **Draw order:** y-sort works as normal.
- **Fit:** contradicts `docs/design.md` ("not one scene node each"). Fine for towers and the base, which are few.

### 2. One `RenderingServer` canvas item per enemy

- Create with `canvas_item_create()`, parent with `canvas_item_set_parent(rid, y_sorted_node.get_canvas_item())`, draw once with `canvas_item_add_texture_rect()`, then each frame update only `canvas_item_set_transform()`. Primitives "can't be modified" once added; only the transform is cheap to change. ([Optimization using Servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html))
- **Draw cost:** same batching as sprites, since the renderer sees the same items.
- **CPU cost:** one server call per enemy per frame for the transform (about 1,000 GDScript-to-engine calls), plus the server's per-frame y-sort of every item in the layer. No scene-tree overhead.
- **Draw order:** `canvas_item_set_sort_children_by_y` is "Equivalent to `CanvasItem.y_sort_enabled`". Children of a y-sorted node, raw or not, are sorted together, so raw enemy items interleave correctly with tower and pile nodes under the same y-sorted parent. ([RenderingServer XML, 4.7.2](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/RenderingServer.xml)) `canvas_item_set_custom_rect` can skip per-item rect recomputation: "Setting a custom visibility rect can reduce CPU load when drawing lots of 2D instances."
- **Lifecycle:** RIDs must be freed with `RenderingServer.free_rid()` on death. Pooling (hide with `canvas_item_set_visible` and reuse) avoids create/free churn.
- **Fit:** matches the data-oriented design. Enemies stay plain data in arrays; only a parallel array of RIDs touches rendering.

### 3. `MultiMeshInstance2D` (or `canvas_item_add_multimesh`)

- One canvas item, one instanced draw call for every enemy.
- **CPU cost:** lowest. The whole frame's instance data can be uploaded in one call with `multimesh_set_buffer()` from a `PackedFloat32Array`: 8 floats per 2D instance, 12 with colour or custom data, 16 with both. ([RenderingServer XML, 4.7.2](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/RenderingServer.xml)) `visible_instance_count` limits drawing without reallocating.
- **Culling:** "there is no screen or frustum culling possible for individual instances"; visibility is all or nothing for the MultiMesh. ([Optimization using MultiMeshes](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)) Not a problem for a map 1.5–2 screens wide.
- **Draw order:** the y-sorter only sees the one canvas item, at the `MultiMeshInstance2D`'s origin. Within the MultiMesh, instances draw in buffer order, so enemies can be sorted among themselves by sorting the buffer on the CPU. Interleaving with towers and piles needs one of:
  - **Row bands:** one MultiMesh per isometric row (or band of rows), each a y-sorted sibling of towers and piles with its origin at the band's Y. Enemies are bucketed into bands each frame. Correct only to band resolution, and the number of draw calls grows with the number of bands.
  - **Everything in sorted buffers:** draw piles and towers through the same instanced path and sort one combined buffer. This means giving up nodes for towers and piles too.
  - **Depth buffer:** not available. 2D canvas rendering has no depth test, so a per-instance Z cannot do the sort on the GPU.
- **Fit:** the fastest raw path, but it pushes the sorting problem onto the game.

### 4. One `_draw()` on a single node (`draw_texture_rect` per enemy, `queue_redraw()` each frame)

- All rects batch into one draw call, but every frame re-records 1,000 commands from GDScript, and the whole set is one canvas item, so it has the same y-sort problem as MultiMesh. Strictly worse than option 3.

### 5. Others

- **`GPUParticles2D`:** draws instanced like a MultiMesh and has the same single-item sorting limit; driving particles from game-state data is awkward. Not a fit.
- **`TileMapLayer` for terrain and piles:** with `y_sort_enabled`, "tiles are grouped by Y position instead" of 16×16 quadrants, so a y-sorted tile layer contributes roughly one canvas item per occupied row and its tiles interleave with enemies in the same y-sorted parent. ([TileMapLayer XML, 4.7.2](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/TileMapLayer.xml)) Flat ground can sit in a non-sorted layer below with a lower `z_index`. `y_sort_origin` shifts the sort point per tile.

## Isometric draw-order notes

- Put enemies, towers and pile blocks under one y-sorted parent at one `z_index`. Flat ground goes on a lower `z_index` and needs no sorting.
- Sort point is the item's origin. Each sprite's origin should sit at its foot (the cell's ground contact), with the texture offset upward. A 2×2 tower should use the origin of its front-most (lowest on screen) point, or it will draw over enemies standing in front of its back half. Multi-cell objects are the classic isometric failure case; splitting a tower into per-cell pieces is the usual fix if one origin is not enough.
- Ties are broken by child order, so enemies on exactly the same Y can flicker only if their sibling order changes. Raw canvas items keep creation order.

## Costs at 1,000 enemies, ranked (reasoned, not measured)

| Option | Draw calls | Per-frame CPU | Y-sort with towers/piles |
|---|---|---|---|
| Sprite2D nodes | few (shared atlas) | high: scene tree + server sort | automatic |
| RS canvas items | few (shared atlas) | medium: 1 call each + server sort | automatic |
| MultiMesh | 1 per MultiMesh | low: 1 buffer upload | manual (bands or custom sort) |
| Single `_draw()` | 1 | medium-high: re-record all | none |

1,000 items is well inside the batching buffer (16,384) and is a small sort. The likely bottleneck at this size is GDScript work per enemy (movement, flow fields, separation), not drawing.

## Version caveats

- RD (Forward+/Mobile) 2D batching exists from 4.4. On 4.0–4.3, option 2 would cost one draw call per item on Forward+. macOS uses the Metal driver for Forward+ from 4.4 onward.
- The official MultiMesh docs page is marked as not yet updated for 4.7.
- Line numbers above refer to the `4.7.2-stable` tag.

## Recommendation

Use option 2 for v1: pooled `RenderingServer` canvas items under a y-sorted parent shared with towers and piles, all textured rects from one atlas. Profile wave 20 (~700 enemies) and a 1,000-enemy stress scene with the Godot profiler and the "Draw Calls" and "Items" monitors. Move to MultiMesh with row bands only if the y-sort or per-item transform calls show up as the bottleneck.
