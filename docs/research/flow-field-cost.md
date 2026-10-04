# Flow field cost in GDScript on a large grid

Research for issue #3. Question: what it costs to compute a flow field (cost, integration and direction fields) in GDScript on 100×100 to 300×300 grids, and how to keep recomputation cheap when one pile changes level. Two fields are needed (sensible and direct). The base is central and the only goal, so one field per route type serves every enemy.

## Answer

- **A full rebuild is too slow to do in a frame above roughly 100×100.** One 8-neighbour Dijkstra integration field plus its direction field takes about 21 ms at 100×100, 88 ms at 200×200 and 204 ms at 300×300 in typed GDScript on an Apple M5 (Godot 4.7.2). The cost grows roughly linearly with cell count, at about 2.3 µs per cell.
- **Incremental repair is fast in the common case.** When one cell changes, an exact repair takes a median of 0.03 ms. The 95th percentile is 0.6 to 2.3 ms, but the worst case is 17 to 19 ms. The worst case happens when the changed cell sits on the shortest-path tree of a large region, for example right beside the base.
- **WorkerThreadPool runs the two fields in parallel almost perfectly.** Two Dijkstra fields take 293 ms one after the other at 300×300, and 149 ms as two `add_task` jobs.
- **Recommendation:** keep cost, integration and direction fields in flat `Packed*Array`s with a padded border. Apply each pile change as an exact incremental repair, batched once per physics tick, to both fields. Do the end-of-wave decay (which changes every pile at once) as a full rebuild on WorkerThreadPool and swap the arrays in when it finishes. If profiling shows that worst-case repairs cause frame spikes, move the repair itself to a worker as well (double-buffered). Time-slicing, as in *Supreme Commander 2*, is a further fallback. Grids of 200×200 or more should be avoided unless the design needs them, because full rebuilds approach a quarter of a second each.

## Measurements

These come from `docs/research/flow_field_bench.gd`, run with `Godot --headless --script docs/research/flow_field_bench.gd` (Godot 4.7.2 stable, Apple M5, macOS). Each figure is the median of 7 runs.

The test map is a random grid: 2% tower cells (impassable), 2% walls (cost 46), and 10% piles at levels 1 to 4 (costs 12, 14, 18 and 25, which is 10 / (1 − slow)). The rest are clear cells (cost 1). Steps cost 10 orthogonally and 14 diagonally, multiplied by the cost of the cell being entered. Diagonal steps may not cut corners. The goal is the centre cell.

| Grid | 4-neighbour BFS, uniform cost (floor) | 8-neighbour Dijkstra (integration) | Direction field | Full field | Two Dijkstra fields, sequential | Two Dijkstra fields, 2 worker tasks |
|---|---|---|---|---|---|---|
| 100×100 | 1.8 ms | 14.7 ms | 6.4 ms | 21.1 ms | 29.6 ms | 15.1 ms |
| 200×200 | 7.1 ms | 62.4 ms | 25.4 ms | 87.8 ms | 125.8 ms | 64.0 ms |
| 300×300 | 16.3 ms | 145.8 ms | 58.5 ms | 204.3 ms | 292.8 ms | 148.8 ms |

The incremental repair figures cover 200 random pile changes applied one after another. Each run was checked against a full rebuild: the integration and direction fields matched exactly at every size.

| Grid | Raise (a body lands): median / p95 / max | Largest region repaired | Lower (decay or wall broken): median / p95 / max |
|---|---|---|---|
| 100×100 | 0.03 / 0.58 / 5.1 ms | 1,619 cells | 0.01 / 0.01 / 0.2 ms |
| 200×200 | 0.03 / 1.79 / 19.1 ms | 5,609 cells | 0.01 / 0.04 / 1.3 ms |
| 300×300 | 0.03 / 2.27 / 17.0 ms | 5,185 cells | 0.01 / 0.02 / 19.0 ms |

Observations:

- **Dijkstra costs about 9× as much as plain BFS.** The overhead comes from the binary heap, the 8 neighbours and the corner checks, all running as interpreted bytecode. A pile-free map could use BFS, but piles carry real costs, so a priority queue is required.
- **The direction field is about 30% of a full build.** It is optional: enemies can instead sample the lowest of their 8 integration neighbours when they move. Emerson's direction field exists to cache this choice for many agents, and with about 1,000 enemies, caching it is likely still worth it.
- **The direction must point at the true shortest-path predecessor**, meaning the neighbour with the lowest integration value plus step cost, not simply the lowest integration value. The first version of the benchmark used the simpler rule, and incremental repair went wrong because the direction pointers no longer formed the shortest-path tree.
- **The cost of a raise depends on where the cell is.** Most cells have small subtrees. A cell next to the base, or one that funnels a corridor, can have thousands of cells downstream of it.
- **Packed arrays are passed by reference in GDScript** (see the [PackedInt32Array docs](https://docs.godotengine.org/en/stable/classes/class_packedint32array.html)), so local aliases of member arrays are free. The exception is a value returned from a built-in property or method, which is a copy.

## Techniques for cheap recomputation

### 1. Exact incremental repair (recommended)

This is the classic dynamic shortest-path approach (Ramalingam and Reps, "An incremental algorithm for a generalization of the shortest-path problem", *Journal of Algorithms* 21(2), 1996; Lifelong Planning A* by Koenig, Likhachev and Furcy, *Artificial Intelligence* 155, 2004, is the heuristic-search relative):

- **Cost goes down** (a pile decays, or a wall is broken): seed the changed cell from its neighbours, then run Dijkstra that only continues while values improve. Only cells that actually get cheaper are touched.
- **Cost goes up** (a body lands, or a pile becomes a wall): walk the direction pointers backwards from the changed cell to collect its subtree, meaning every cell whose route passes through it. Reset those cells to infinity, seed them from their valid neighbours outside the subtree, and run Dijkstra over them.
- Then recompute directions for the changed cells and their neighbours.

When several piles change in one tick, their subtrees can be combined and repaired in a single pass. This is cheaper than repairing them one at a time, because overlapping regions are only processed once. At wave 20 (about 700 enemies), bodies arrive in bursts, so the repair should run once per tick rather than once per kill.

### 2. Full rebuild on WorkerThreadPool

The Godot docs describe [WorkerThreadPool](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html) as "A singleton that allocates some Threads on startup, used to offload tasks to these threads". Every task must be waited on with `wait_for_task_completion()` "so that any allocated resources inside the task can be cleaned up". The measured 1.97× speed-up for two tasks confirms that GDScript runs truly in parallel across worker threads.

The [thread-safe APIs page](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html) states that, for arrays, "Reading and writing elements from multiple threads is OK, but anything that changes the container size ... requires locking a mutex". It also states that "Interacting with the active scene tree is **not** thread-safe."

The safe pattern is therefore:

1. Hand each task a snapshot of the cost field.
2. Let each task allocate its own integration and direction arrays.
3. On the main thread, poll `is_task_completed()`, then swap in the new arrays and call `wait_for_task_completion()`.

Enemies keep using the previous field until the swap. One rebuild takes about 150 ms of wall time at 300×300, so they would follow a stale field for roughly 9 frames.

This approach suits the end-of-wave decay, when every pile changes at once and no enemies are on the map. It also works as a fallback if incremental bookkeeping proves fragile.

### 3. Recompute on a timer

A full rebuild every N ms bounds the CPU cost, but it is wasteful (most of each rebuild is unchanged) and it leaves enemies walking into new piles until the next rebuild. Incremental repair dominates it on both cost and freshness. The useful idea here is **batching**: collect the changes made during a tick and process them together, which costs nothing in responsiveness at 60 ticks per second.

### 4. Sectors and time-slicing (Emerson, *Supreme Commander 2*)

Emerson's [Game AI Pro chapter 23](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter23_Crowd_Pathfinding_and_Steering_Using_Flow_Field_Tiles.pdf) splits the world into 10 × 10 sectors with portal windows between them. It uses an 8-bit cost field "in the range 0–255, where 255 is a special case that is used to represent walls", a 24-bit integration field, and an 8-bit flow field (a 4-bit direction index plus flags). Integration is a wavefront ("Eikonal") pass over 4-neighbours, preceded by a line-of-sight pass. Line of sight there means cells with a straight, unblocked line to the goal, which can head straight for it instead of following the integration field.

The chapter covers changes and CPU budget:

- Changes are handled by "marking the cost field of the sector that contains them and their associated portals as dirty", then rebuilding affected portals and paths "based on a priority queue, where each item in the queue is given a time slice of a fixed number of milliseconds."
- It notes that CPU use can be capped "by capping the number of tiles or grid squares you commit to per tick" and that integration "can easily [be spread] across threads because the Integration Field memory is separate from everything else."

Sectors exist to serve many goals on huge maps, where each path request only integrates the sectors along its portal route. pile-up has one goal, so a single whole-map field is simpler, and sectors would add nothing except a coarse version of dirty-region tracking. The ideas worth borrowing are time-slicing and the compact byte layouts.

### Not available natively

[AStarGrid2D](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html) is "An implementation of A\* for finding the shortest path between two points". It only returns point-to-point paths (`get_id_path`, `get_point_path`) and offers no cost-to-goal field for every cell, so it cannot replace the integration pass. If GDScript ever proves too slow, the next step is to port only the integration kernel to a GDExtension (C++) or C#. That is not needed at the grid sizes measured here.

## Implementation notes for the prototype

- Use typed GDScript throughout. The [static typing docs](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html) say "typed GDScript improves performance by using optimized opcodes when operand/argument types are known at compile time". The benchmark is fully typed. Iterating an untyped Dictionary breaks `:=` type inference (a parse error in the benchmark's first draft), so it uses `Dictionary[int, bool]`.
- Store cells as a flat index `y * width + x`, with a one-cell impassable border, so the neighbour loop needs no bounds checks.
- Pack the heap keys as `(dist << 24) | index` in a `PackedInt64Array`, so the heap is a single array of ints with no objects.
- Both fields share the topology (the towers) and differ only in their per-level cost tables, so the update code is the same for both. Only the cost lookup differs.
- Dial's bucket queue (buckets indexed by integer distance in place of a heap) could replace the binary heap, because costs are small integers. This was not measured.

## Open questions for other tickets

- The grid size is not yet fixed. The design says the map is "roughly 1.5–2 screens wide" and that a tower occupies 2×2 cells. Choosing 100×100 to 150×150 keeps full rebuilds under about 50 ms.
- The cost values are placeholders. In particular, the sensible wall cost (about 30 s to break at 1.5 cells/s) and the direct-route pile costs need tuning.
