# pile-up

An isometric, wave-based tower defence game where every kill leaves a body. Bodies pile up into terrain that slows enemies and grows into walls they must break through.

Built with Godot 4 and GDScript. Currently a prototype.

See [docs/design.md](docs/design.md) for the full design.

## Building

The enemy neighbour scan is a C++ GDExtension in `native/` ([ADR 0001](docs/adr/0001-enemies-as-packed-arrays.md)). Build it into `bin/` before opening the project:

```sh
git submodule update --init
brew install scons   # or: pip install scons
scons -C native target=template_release
```

Without it the game falls back to the slower GDScript scan, and the native scan tests fail. CI builds it for Linux, macOS and Windows.
