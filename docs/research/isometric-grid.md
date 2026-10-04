# Isometric grid in Godot 4.7

Research for issue #4. Checked against Godot 4.7.2-stable (class reference, engine source at tag `4.7.2-stable`, and a headless test run on 4.7.2).

## Answer

Use a `TileMapLayer` with an isometric `TileSet` (`TILE_SHAPE_ISOMETRIC`, `TILE_LAYOUT_DIAMOND_DOWN`) for drawing ground and piles, and a single `Transform2D` owned by a grid helper for all cell/world maths. The two agree exactly (verified below), so the TileMapLayer is purely a renderer and the logical grid never depends on a node.

- **Cells to world:** `xf * (Vector2(cell) + Vector2(0.5, 0.5))`, identical to `TileMapLayer.map_to_local(cell)`.
- **World to cell:** `Vector2i((xf.affine_inverse() * pos).floor())`, identical to `TileMapLayer.local_to_map(pos)`.
- **Continuous grid position** (smooth enemies, flow fields, spatial hash): `xf.affine_inverse() * pos` without the floor. TileMapLayer has no float equivalent, which is why the transform exists.
- **Mouse picking:** `get_global_mouse_position()` (already accounts for the Camera2D), then to the layer's local space, then world to cell.
- **Camera:** one `Camera2D`; pan by dragging or edge keys, zoom with the wheel, both handled in `_unhandled_input` so UI gets events first.
- **Per-cell pile levels:** a second `TileMapLayer` whose atlas holds the five pile tiles; changing a level is one `set_cell` (or `erase_cell`). Updates are batched at end of frame and only rebuild the affected rendering quadrant.

## TileMapLayer vs TileMap (version caveat)

`TileMap` is deprecated. Godot 4.3 introduced the `TileMapLayer` node "to replace the old approach completely"; the old node is still supported for compatibility ([4.3 release notes](https://godotengine.org/releases/4.3/)). The 4.7.2 class reference marks `TileMap` as `deprecated="Use multiple [TileMapLayer] nodes instead."` ([`doc/classes/TileMap.xml`](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/TileMap.xml)). Tutorials and forum answers written for 4.0–4.2 use `TileMap` with integer layer arguments (`set_cell(layer, coords, ...)`); in 4.7 each layer is its own node and the layer argument is gone.

## Isometric TileSet settings

- `tile_shape = TILE_SHAPE_ISOMETRIC`: "Diamond tile shape (for isometric look)" ([TileSet](https://docs.godotengine.org/en/latest/classes/class_tileset.html)).
- `tile_layout`: the **default is `TILE_LAYOUT_STACKED`**, which gives staggered rows (a zigzag map), not a diamond. For a rotated square grid where cell `(x, y)` behaves like an ordinary 2D array, set `TILE_LAYOUT_DIAMOND_DOWN`: "the horizontal axis goes down-right, and the vertical one goes down-left" (same page). Confirmed default `0 = STACKED` in the test run.
- `tile_size`: the diamond's bounding box, conventionally 2:1 (e.g. `Vector2i(64, 32)`).
- The class reference notes an isometric TileSet "works best if all sibling TileMapLayers and their parent inheriting from Node2D have Y-sort enabled" (same page).

## Cell and world conversion

From [`TileSet::map_to_local`](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/2d/tile_set.cpp#L1547) for isometric + horizontal offset axis + `DIAMOND_DOWN`:

```
local = (((x - y) / 2 + 0.5) * W,  ((x + y) / 2 + 0.5) * H)
```

It "Returns the centered position of a cell" ([TileMapLayer](https://docs.godotengine.org/en/latest/classes/class_tilemaplayer.html)). Note the `+ 0.5`: cell `(0, 0)`'s centre is at `(W/2, H/2)`, not the origin, so the top vertex of cell `(0, 0)` sits at `(W/2, 0)`.

[`TileSet::local_to_map`](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/resources/2d/tile_set.cpp#L1620) is diamond-aware (it corrects for the triangle corners of the bounding box), so it returns the exact diamond under a point, not the bounding rectangle.

The equivalent affine transform, mapping continuous grid coordinates to layer-local pixels:

```gdscript
var xf := Transform2D(Vector2(W / 2, H / 2), Vector2(-W / 2, H / 2), Vector2(W / 2, 0))
```

**Verified** with a headless script on Godot 4.7.2 (`W = 64, H = 32`): `map_to_local` matched `xf * (cell + 0.5)` for all 1,600 cells in `[-20, 20)²`, and `local_to_map` matched `floor(xf.affine_inverse() * p)` for 200,000 random points. Zero mismatches.

### TileMapLayer isometric mode vs a custom transform

| | TileMapLayer only | Custom transform only | Both (recommended) |
|---|---|---|---|
| Drawing many cells | Batched, quadrant-cached | Must be built by hand | TileMapLayer |
| Integer cell lookup | `local_to_map` | `floor(inverse * p)` | Either, they agree |
| Float grid position for smooth movement | Not available | Yes | Transform |
| Logic testable without a scene tree | No, needs a node | Yes | Transform |

The transform is the source of truth; the TileMapLayer is configured to match it and is only used for rendering. This keeps the simulation (flow fields, spatial hash, ~1,000 enemies as plain data) free of node calls.

## Picking the cell under the mouse

`CanvasItem.get_global_mouse_position()` returns the cursor "in global 2D space" and `get_local_mouse_position()` returns it in the node's local space ([CanvasItem](https://docs.godotengine.org/en/latest/classes/class_canvasitem.html)). Both already include the active Camera2D's pan and zoom, so no manual camera maths is needed:

```gdscript
var cell := ground.local_to_map(ground.get_local_mouse_position())
# or, through the grid helper:
var cell := Vector2i((xf.affine_inverse() * ground.to_local(get_global_mouse_position())).floor())
```

For a position carried by an `InputEvent` rather than the current cursor, `CanvasItem.make_input_local()` converts event coordinates into the node's local space ([Viewport and canvas transforms](https://docs.godotengine.org/en/latest/tutorials/2d/2d_transforms.html)).

## Camera pan and zoom

A single `Camera2D`:

- `zoom`: "Higher values are more zoomed in. For example, a zoom of `Vector2(2.0, 2.0)` will be twice as zoomed in on each axis" ([Camera2D](https://docs.godotengine.org/en/latest/classes/class_camera2d.html)). Clamp it, e.g. 0.5–2.
- `limit_left/top/right/bottom` stop the view leaving the map; `position_smoothing_enabled` eases movement (same page).
- Drag-pan: on `InputEventMouseMotion` with the pan button held, `camera.position -= event.relative / camera.zoom` (screen pixels divided by zoom gives world pixels).
- Zoom towards the cursor: record `get_global_mouse_position()` before changing `zoom`, read it again after, and add the difference to `camera.position`.
- Handle these in `_unhandled_input`: "for gameplay input, `Node._unhandled_input()` is generally a better fit, because it allows the GUI to intercept the events" ([InputEvent](https://docs.godotengine.org/en/latest/tutorials/inputs/inputevent.html)).

## Drawing per-cell pile levels that change often

### How TileMapLayer handles updates

- `set_cell(coords, source_id, atlas_coords, alternative)`; source `-1` (or `erase_cell`) removes the tile ([TileMapLayer](https://docs.godotengine.org/en/latest/classes/class_tilemaplayer.html)).
- "For performance reasons, all TileMap updates are batched at the end of a frame" (same page). `update_internals()` forces an immediate update and is not needed here.
- In source, `set_cell` adds only that cell to a dirty list; at end of frame only the [rendering quadrants containing dirty cells](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/2d/tile_map_layer.cpp#L270) have their canvas items freed and rebuilt. Without Y-sort a quadrant is `rendering_quadrant_size` cells square (default 16). **With Y-sort enabled, quadrants are keyed by the cell's Y draw position instead** ([source](https://github.com/godotengine/godot/blob/4.7.2-stable/scene/2d/tile_map_layer.cpp#L551)), so a change rebuilds one isometric row, and `rendering_quadrant_size` becomes read-only in the inspector.
- Twenty piles changing in one frame cost at most twenty small quadrant rebuilds, once, at end of frame. Piles that do not change cost nothing per frame.

### Options compared

1. **Pile TileMapLayer with a 5-tile atlas (recommended).** Atlas column `level - 1` holds the stacked-blocks drawing for that level, darkening as it rises. Level change = `set_cell(cell, 0, Vector2i(level - 1, 0))`; level 0 = `erase_cell(cell)`. Use each tile's Texture Origin to lift the taller stacks and Y Sort Origin so they sort by their footprint ([Using TileSets](https://docs.godotengine.org/en/latest/tutorials/2d/using_tilesets.html)). Use atlas tiles only: "scene tiles come with a greater performance overhead compared to atlases, as every scene is instantiated individually for every placed tile" (same page). The placeholder art is one small PNG (five coloured block stacks), or an `Image` filled in code and wrapped in an `ImageTexture` at startup.
2. **One Node2D with `_draw()`.** Draw commands "are cached and remembered"; a change calls `queue_redraw()`, which re-runs the whole `_draw()` once that frame ([Custom drawing in 2D](https://docs.godotengine.org/en/latest/tutorials/2d/custom_drawing_in_2d.html)). Drawing hundreds of polygons is cheap and needs no texture, but every change redraws every pile and the whole node is one draw item, so piles cannot Y-sort against other things. Good fallback for debug overlays (flow field arrows, grid lines).
3. **MultiMeshInstance2D.** Suited to the enemies, not piles: piles are few and change rarely per frame, and a MultiMesh is also a single canvas item for sorting.
4. **One node per pile (Polygon2D/Sprite2D).** Works but scales worst and adds node churn when walls break and piles spawn. Not recommended.

## Depth sorting caveat (for the enemy-rendering ticket)

`y_sort_enabled`: "this and child CanvasItem nodes with a higher Y position are rendered in front of nodes with a lower Y position" ([CanvasItem](https://docs.godotengine.org/en/latest/classes/class_canvasitem.html)). Sorting is per canvas item. A Y-sorted TileMapLayer exposes one item per row, so tall pile tiles occlude correctly against other Y-sorted nodes, but enemies drawn as one `MultiMeshInstance2D` (as the design proposes for 1,000 enemies) are one item at one Y and cannot interleave with pile rows. Enemies will draw entirely in front of or entirely behind piles. For flat placeholder shapes this is likely acceptable (draw enemies above ground, piles with low enough height), but it should be decided when enemy rendering is researched, e.g. by splitting enemies into per-row MultiMeshes or accepting the overlap.

## Sources

- Godot 4.3 release notes: https://godotengine.org/releases/4.3/
- TileMapLayer class reference: https://docs.godotengine.org/en/latest/classes/class_tilemaplayer.html
- TileSet class reference: https://docs.godotengine.org/en/latest/classes/class_tileset.html
- Using TileSets: https://docs.godotengine.org/en/latest/tutorials/2d/using_tilesets.html
- Camera2D class reference: https://docs.godotengine.org/en/latest/classes/class_camera2d.html
- CanvasItem class reference: https://docs.godotengine.org/en/latest/classes/class_canvasitem.html
- Viewport and canvas transforms: https://docs.godotengine.org/en/latest/tutorials/2d/2d_transforms.html
- Custom drawing in 2D: https://docs.godotengine.org/en/latest/tutorials/2d/custom_drawing_in_2d.html
- Using InputEvent: https://docs.godotengine.org/en/latest/tutorials/inputs/inputevent.html
- MultiMeshInstance2D class reference: https://docs.godotengine.org/en/latest/classes/class_multimeshinstance2d.html
- Engine source, `4.7.2-stable`: `scene/resources/2d/tile_set.cpp`, `scene/2d/tile_map_layer.cpp`, `doc/classes/TileMap.xml`
