# pile-up

An isometric, wave-based tower defence game where every kill leaves a body, and bodies pile up into terrain that shapes how enemies move.

## Language

### The map

**Cell**:
One square of the logical grid that everything in the game sits on.
_Avoid_: Tile (reserved for the drawn isometric diamond)

**Base**:
The central structure being defended; it has a number of lives.
_Avoid_: Core, HQ

**Rock**:
A cell that is part of the map itself: no enemy can enter it, and nothing can be built or land on it. It never changes.
_Avoid_: Obstacle, blocked cell, wall

**Spawn edge**:
A map edge that enemies enter from during the current wave.

### Power

**Power grid**:
The cells powered from the base, plus any further cells powered by buildings that the grid still connects to the base. Building is only allowed on the power grid.
_Avoid_: Build zone, power zone, paint

**Powered**:
A building the power grid connects to the base. A building cut off from the base is **unpowered** and stops working.

**Pylon**:
A building whose only job is to extend the power grid, much further than other buildings do.

### Bodies

**Body**:
What one killed enemy adds to the world; the single unit a pile is made of. "Corpse" is an accepted synonym in player-facing text.

**Pile**:
The stack of bodies on one cell, described by its level from 1 to 5.
_Avoid_: Mound, stack, height

**Level**:
The number of bodies in a pile, which sets how much it slows enemies.

**Wall**:
A pile at level 5. It is a state of a pile, not a separate object.
_Avoid_: Barricade

### Enemies

**Leak**:
An enemy reaching the base and costing a life.

**Sensible route**:
The default route enemies follow, where piles and walls cost what they really cost.

**Direct route**:
The alternative route where piles are cheap and walls are worth breaking; an enemy that rolls into it commits until it is past the obstacle.
_Avoid_: Reckless, personality

### Flow of play

**Run**:
One game, from the first wave until the base runs out of lives. A restart begins a new run.
_Avoid_: Game, match, session

**Wave**:
One spawned group of enemies, from pressing "next wave" until the last of them dies or leaks.
_Avoid_: Round, level

**Build phase**:
The time between waves.
_Avoid_: Intermission
