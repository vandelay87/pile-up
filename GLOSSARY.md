# pile-up

An isometric, wave-based tower defence game where every kill leaves a body, and bodies pile up into terrain that shapes how enemies move.

## Language

### The map

**Cell**:
One square of the logical grid that everything in the game sits on.
_Avoid_: Tile (reserved for the drawn isometric diamond)

**Base**:
The central structure being defended. Enemies attack it like any other structure, and the run ends when it is destroyed.
_Avoid_: Core, HQ

**Rock**:
A cell that is part of the map itself: no enemy can enter it, and nothing can be built or land on it. It never changes.
_Avoid_: Obstacle, blocked cell, wall

**Spawn edge**:
A map edge that enemies enter from during the current wave.

### Structures

**Structure**:
Anything with HP that enemies attack when it is in their way: a wall, a building or the base.
_Avoid_: Target, obstacle

**Building**:
Anything the player builds: a tower or a pylon.
_Avoid_: Structure (which also covers walls and the base)

### Power

**Power grid**:
The power areas of the base and of every powered building. Building is only allowed on the power grid.
_Avoid_: Build zone, power zone, paint

**Power area**:
The square of cells that the base or one building powers around itself. A pylon's power area is much larger than a tower's.
_Avoid_: Radius, range (range belongs to towers' fire)

**Powered**:
A building that has a cell in the power area of the base or of another powered building. A building cut off from the base is **unpowered** and stops working.

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

**Sensible route**:
The default route enemies follow, where piles and walls cost what they really cost.

**Direct route**:
The alternative route where piles are cheap and walls are worth breaking; an enemy that rolls into it commits until it is past the obstacle.
_Avoid_: Reckless, personality

### Flow of play

**Run**:
One game, from the first wave until the base is destroyed. A restart begins a new run.
_Avoid_: Game, match, session

**Wave**:
One spawned group of enemies, from pressing "next wave" until the last of them dies.
_Avoid_: Round, level

**Build phase**:
The time between waves.
_Avoid_: Intermission

**Enemies left**:
The enemies in the current wave not yet killed, including those not yet spawned.

**Wave tail**:
The end of a wave, once Enemies left falls to a set count, which grows with the wave number.
_Avoid_: Endgame, stragglers

### Economy

**Bounty**:
The gold one kill pays before any combo.

**Combo**:
The multiplier on bounty, set by how many kills happened recently. It rises with bursts of killing and falls as they stop.
_Avoid_: Streak, chain
