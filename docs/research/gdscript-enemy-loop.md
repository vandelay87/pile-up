# Can GDScript move 1,000 enemies within budget?

Research for issue #6. Question: can typed GDScript update about 1,000 enemies per frame (flow-field lookup, spatial-hash separation, slow from piles) and leave most of a 60 fps frame for everything else? If not, what would moving the loop to C# or C++ cost?

## Answer

Yes, with a wide margin. On an Apple M5 running the Godot 4.7.2 editor binary headless, a typed GDScript loop over 1,000 enemies costs **0.9 ms per frame when spread out and 1.8 ms when packed into a dense crowd**, about 5–11% of the 16.7 ms budget at 60 fps. At 2,000 enemies in a dense crowd it costs 5.7 ms (about 34%), which still fits but leaves noticeably less room.

**Recommendation: stay in GDScript.** C# is not needed for the v1 target. Keep the enemy loop data-oriented (packed arrays, one batched render buffer) and behind one module, so the hot loop could later move to a GDExtension if profiling of the real game says so.

## Benchmark

Script: [`gdscript-enemy-loop/enemy_loop_bench.gd`](gdscript-enemy-loop/enemy_loop_bench.gd). Run from the repo root:

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script docs/research/gdscript-enemy-loop/enemy_loop_bench.gd
```

What one frame does, all in statically typed GDScript:

1. **Hash build**: a linked-list spatial hash keyed by grid cell (`PackedInt32Array` head per cell plus next per agent), rebuilt every frame in one O(n) pass.
2. **Move and separate**: per agent, read position from `PackedFloat32Array`s, look up the direction in one of two `PackedVector2Array` flow fields (sensible or direct, chosen per agent), apply the pile slow from a `PackedByteArray` of levels, accumulate separation from every agent in the 3×3 neighbouring cells within 0.6 cells, block on walls, roll the 5% switch to the direct route when entering a pile, and respawn at an edge on reaching the base.
3. **Render buffer**: write an isometric 2D transform per agent into a `PackedFloat32Array` and hand it to `RenderingServer.multimesh_set_buffer()` in one call.

World: 128×96 cell grid, 400 random piles of level 1–5. Each run has 120 warm-up frames then 600 measured frames. "Spread" starts agents uniformly across the map; "dense" starts them all in a 24×24-cell block so separation has many neighbours to check.

### Results

Apple M5 (10 cores, one used), Godot 4.7.2.stable.official, editor binary (`OS.is_debug_build()` is true). Milliseconds per frame. Mean and p95 are from the second of two runs (they agreed within a few percent); Max shows the range across both.

| Agents | Scenario | Neighbours checked / agent | Mean | p95 | Max |
|---|---|---|---|---|---|
| 1,000 | spread | 1.9 | 0.89 | 1.00 | 1.04–1.95 |
| 1,000 | dense | 14.9 | 1.84 | 1.88 | 2.13–3.68 |
| 2,000 | spread | 3.7 | 2.10 | 2.50 | 4.60–4.83 |
| 2,000 | dense | 27.9 | 5.75 | 6.31 | 8.81–10.85 |
| 1,000 | dense, **untyped** | 14.8 | 2.97 | 3.20 | 4.88–4.98 |

Breakdown for 1,000 dense: hash build 0.04 ms, move and separation 1.72 ms, render buffer 0.08 ms. Separation dominates; each neighbour check costs roughly 0.1 µs, so cost grows with crowd density as well as with count. Doubling the count in the dense case triples the cost because density (neighbours per agent) also doubles.

Removing static types from the same loop makes it about 60% slower (1.84 ms to 2.97 ms), which matches the official claim below that typed code uses optimized opcodes.

### Caveats

- **Debug binary.** The editor binary runs GDScript with debug checks. A release export template should be no slower; it was not measured because no export templates are installed. The numbers are therefore conservative.
- **No GPU work.** Headless uses a dummy renderer, so `multimesh_set_buffer` measures only the script side. Drawing 1,000 instances through one MultiMesh is a single draw call (see sources).
- **Not the whole enemy simulation.** Tower targeting, wall attacks, body spill and flow-field rebuilds when piles change are not included. Flow-field rebuilds happen only when a pile changes level, not every frame, so they belong in a separate measurement.
- **Single thread.** The loop runs on one core; nothing here uses `WorkerThreadPool`.
- **Synthetic crowding.** Real crowds near the base or at walls may be denser than the "dense" case. Capping the neighbours checked per agent (for example, stop after 8) bounds the worst case at little visual cost.

## What the primary sources say

- **Typed GDScript is faster.** "Typed GDScript improves performance by using optimized opcodes when operand/argument types are known at compile time." ([Static typing in GDScript](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html))
- **Packed arrays suit this data.** "PackedArrays are generally faster to iterate on and modify compared to a typed Array of the same type" and they "consume less memory". ([GDScript reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html))
- **The language is rarely the bottleneck.** "In most games, the scripting language itself is not the cause of performance problems." ([FAQ](https://docs.godotengine.org/en/stable/about/faq.html))
- **Data-oriented design matters at tens of thousands, not one thousand.** DOD "can only provide significant performance improvements when dealing with dozens of thousands of objects which are processed every frame with little modification." For that scale the FAQ recommends "C++ and GDExtensions for performance-heavy tasks and GDScript (or C#) for the rest of the game." ([FAQ](https://docs.godotengine.org/en/stable/about/faq.html)) The v1 target of about 1,000 is an order of magnitude below that.
- **MultiMesh batches the drawing.** "A MultiMesh is a single draw primitive that can draw up to millions of objects in one go." The same page notes that setting all instance state with `RenderingServer.multimesh_set_buffer()` "should be extremely efficient". ([Optimization using MultiMeshes](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html))
- **Measure, then optimize.** "Always use profiling and timing to guide your efforts." ([General optimization tips](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html))

## If the loop ever has to move

### C# (.NET build of Godot)

- **Speed.** "The C# language itself tends to be faster than GDScript, which means that C# can be faster in situations with few calls to Godot engine code." A pure-math loop over arrays is that situation. ([FAQ](https://docs.godotengine.org/en/stable/about/faq.html))
- **Whole-project switch.** C# needs "the .NET-enabled version of Godot" and a separately installed .NET SDK; the docs state .NET 8 or later. The project, the editor download and CI all move to the .NET build, not just the hot loop. ([C# basics](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_basics.html))
- **Platforms.** "Projects written in C# using Godot 4 currently cannot be exported to the web platform." Mobile is "experimental". Desktop (the stated target) is unaffected. ([C# basics](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_basics.html))
- **Interop costs.** "C# can be slower than GDScript when making many Godot API calls, due to the cost of marshalling", and passing raw arrays to Godot's API is "comparatively pricey". The render buffer would cross that boundary every frame. ([FAQ](https://docs.godotengine.org/en/stable/about/faq.html), [C# basics](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_basics.html))
- **GC stutter.** "C#'s performance can also be brought down by garbage collection which occurs at random and unpredictable moments." A hot loop must avoid allocating. ([FAQ](https://docs.godotengine.org/en/stable/about/faq.html))

### C++ (GDExtension)

- **Speed.** "C++, using GDExtension, will almost always be faster than either C# or GDScript." ([FAQ](https://docs.godotengine.org/en/stable/about/faq.html))
- **Local change.** It works with the standard Godot build and "doesn't require compiling the engine's source code"; "you can use the same compiled GDExtension library in the editor and exported project". Only the hot loop moves; the rest stays GDScript. ([What is GDExtension?](https://docs.godotengine.org/en/4.4/tutorials/scripting/gdextension/what_is_gdextension.html))
- **Build cost.** Native libraries have to be compiled for each target platform (macOS and Windows here) and kept compatible with the engine version through godot-cpp. This adds a C++ toolchain and a build step to a project that has none. ([What is GDExtension? (latest)](https://docs.godotengine.org/en/latest/engine_details/engine_api/gdextension/what_is_gdextension.html))

### Comparison

| | GDScript (typed) | C# (.NET build) | C++ (GDExtension) |
|---|---|---|---|
| Measured, 1,000 dense | 1.8 ms | not measured | not measured |
| Scope of change | none | whole project and editor | one native library |
| Extra tooling | none | .NET 8+ SDK | C++ toolchain, godot-cpp, per-platform builds |
| Per-frame risks | interpreter overhead | marshalling, GC pauses | none beyond build upkeep |
| Web export | yes | no | needs a web build of the library |

If profiling of the real game ever shows the enemy update above roughly 4 ms at p95, the cheaper first steps are capping neighbour checks and splitting separation across frames. Past that, a GDExtension for this one loop is the better fit than C#: it keeps the standard editor, avoids GC and marshalling on the render buffer, and the packed-array layout already maps directly onto C++ arrays.
