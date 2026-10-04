# Enemies are packed arrays in one module, not scene nodes

Enemies live as parallel typed packed arrays (dense, swap-remove on death, stable ids through an id→index lookup) inside a single enemy module, which other systems reach only through a narrow interface. Each enemy is drawn as one pooled `RenderingServer` canvas item under the y-sorted parent shared with piles and towers, so draw order works without MultiMesh. The hot loop stays in typed GDScript: it measured 0.9–1.8 ms per frame for 1,000 enemies on the baseline M5, and the spike held 60 fps up to about 6,000.

## Considered Options

- **One node per enemy** (the idiomatic Godot approach): rejected for per-node overhead at 1,000+ enemies.
- **MultiMesh**: cheapest to upload, but it y-sorts as a single item, so enemies could not interleave with piles and towers.
- **C# for the hot loop**: needs the .NET editor build and adds GC pauses. If the loop ever has to leave GDScript, it moves to a C++ GDExtension behind the same module.

Evidence: [Drawing 1,000+ enemies](https://github.com/vandelay87/pile-up/issues/2), [Can GDScript move 1,000 enemies within budget?](https://github.com/vandelay87/pile-up/issues/6), [Spike: 1,000 enemies on a flow field](https://github.com/vandelay87/pile-up/issues/7).
