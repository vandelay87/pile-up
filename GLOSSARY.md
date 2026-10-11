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
Anything the player builds: a tower, a pylon, a repair yard or a grinder.
_Avoid_: Structure (which also covers walls and the base)

**Repair yard**:
A building that restores HP to the other buildings around it. It never repairs itself, walls or the base.
_Avoid_: Healer, medic

**Grinder**:
A building that hurts every enemy touching it, including those tumbling over it.
_Avoid_: Trap (enemies press against it, they don't step on it), spike wall (a wall is a pile)

**Repair**:
Restoring HP to a damaged building. Only buildings are repaired.
_Avoid_: Heal

**Drone**:
A repair yard's unit that flies out to one damaged building, repairs it to full and flies back.

**Assignment**:
A building the player has chosen for a repair yard's drone to repair first whenever it is damaged. Without one, the drone picks for itself.
_Avoid_: Target, priority

**Repair threshold**:
A repair yard's setting: its drone only picks a building whose HP has fallen below this share of its max HP, then repairs it to full. It applies to the yard's assignment too.
_Avoid_: Heal threshold, trigger

**Under repair**:
A building with a drone repairing it. It stops working until the drone lifts off, as if unpowered, except a pylon, which keeps powering.
_Avoid_: Offline, disabled

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

**Decay**:
A pile losing a level at the end of a wave, decided by a roll.
_Avoid_: Shrink

### Enemies

**Sensible route**:
The default route enemies follow, where piles and walls cost what they really cost.

**Direct route**:
The alternative route where piles are cheap and walls are worth breaking; an enemy that rolls into it commits until it is past the obstacle.
_Avoid_: Reckless, personality

**Crush**:
A dense, stalled crowd of living enemies pressed against a wall or building, one per connected run of them. The base never has one: enemies there have arrived. "Mob" and "swarm" are informal words for enemies, not for a crush.
_Avoid_: Pile up, jam, clump (piles are bodies; a crush is alive)

**Pressure**:
How close a crush is to overflowing, shown as a gauge above it. It rises while the crush stays stalled, faster the bigger the crush, and drops as its enemies overflow.
_Avoid_: Density meter, stress

**Overflow**:
Enemies from a crush at breaking point tumbling over the wall or building in their way, into the nearest free cell towards their destination.
_Avoid_: Spill-over, climb, breach

**Tumble**:
One enemy's fall over the wall or building in front of it during an overflow, from leaving the crush to landing on a free cell beyond. It falls faster than walking and can be shot on the way. "Tumble" still fits when the far side is lower or a pile.
_Avoid_: Climb, climber, jump

**Overflow tier**:
How hard a crush is overflowing, read from its pressure: a **trickle** (one enemy now and then), a **stream** (a steady line) or a **surge** (the front ranks pouring over together).
_Avoid_: Stage, phase

**Bloater**:
A second type of enemy that blows up when it dies, or by itself after a short fuse once it reaches a structure in its way. Its blast kills enemies, damages buildings and erases piles and walls, and it leaves no body.
_Avoid_: Bomber, kamikaze, creeper, exploding enemy

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
A building's own multiplier on the bounty of its kills, set by how many kills that building made in an unbroken run. It breaks back to nothing when the building goes too long without a kill. Each building has its own; there is no combo for the whole defence.
_Avoid_: Streak, chain, global combo
