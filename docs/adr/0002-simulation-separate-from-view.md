# The simulation is node-free and separate from the view

All game rules live in a `Simulation` object (`RefCounted`) under `src/sim/`, which owns every system, their seeded RNGs and the tick driver. Nothing under `src/sim/` extends `Node` or `Resource` or references `src/view/`; a lint step enforces this. The view layer under `src/view/` draws the simulation and turns input into commands, but never changes simulation state directly.

- **Commands:** player and debug-panel input is queued as commands and drained at step 0 of the next tick, so a seed plus a list of (tick, command) pairs replays a run exactly.
- **Inside the simulation:** systems never connect to each other by signal. The tick driver calls them in a fixed order and passes data between them explicitly (for example, the enemy module's removal step returns lists of deaths and leaks, which the driver hands to the pile system and the run state).
- **Out to the view:** the simulation emits signals for sparse changes (pile levels, towers, gold, lives, phase, rejected commands) at the end of a tick. The enemy renderer reads the enemy module's packed arrays read-only each frame instead.
- **Restart:** a new run builds a fresh `Simulation`; no system supports resetting itself.

## Considered Options

- **Systems as nodes in the main scene** (the idiomatic Godot approach): rejected because the headless tests and the CI simulation budget need the whole tick to run without a scene tree, and node callbacks make tick order implicit.
- **Direct calls from input into the simulation:** simpler, but input would land mid-tick at times set by the engine, breaking deterministic replays.
- **Signals between systems:** loosely coupled, but they hide each tick's data flow across many connections and make a single system harder to test alone.

Evidence: [Code organisation and system boundaries](https://github.com/vandelay87/pile-up/issues/11).
