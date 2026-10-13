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

**No-build cell**:
Clear ground that enemies walk on but nothing can be built on. The map marks a margin of them along each spawn edge.
_Avoid_: Buffer zone, safe zone

### Structures

**Structure**:
Anything with HP that enemies attack when it is in their way: a wall, a building or the base.
_Avoid_: Target, obstacle

**Building**:
Anything the player builds: a tower, a pylon, a repair yard, a grinder or a barracks.
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
A repair yard's machine that flies out to one damaged building, repairs it to full and flies back.

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
What one killed enemy or dead soldier adds to the world; the single unit a pile is made of. "Corpse" is an accepted synonym in player-facing text.

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

**Barrier**:
A connected stretch of walls and buildings, touching side to side or corner to corner. Piles below a wall, rock and the base are never part of one.
_Avoid_: Run (a run is one game), wall line, cluster

**Crush**:
A dense, stalled crowd of living enemies pressed against a barrier, one per barrier. The base never has one: enemies there have arrived. "Mob" and "swarm" are informal words for enemies, not for a crush.
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
A second type of enemy that blows up when it dies, or by itself after a short fuse once it reaches a structure or a soldier in its way. Its blast kills enemies, damages buildings and soldiers, and erases piles and walls, and it leaves no body.
_Avoid_: Bomber, kamikaze, creeper, exploding enemy

### Units

**Unit**:
Anything the player trains and gives orders to. Each one is selected and ordered on its own or as part of a selection. A repair yard's drone is not a unit.
_Avoid_: Troop, minion

**Soldier**:
The one kind of unit in v4: it shoots enemies in range like a tower, and only moves when ordered. Enemies attack it when it is in their way, as they do a structure, but it is not one.
_Avoid_: Fire squad (nothing groups soldiers except the player's selection), marine, trooper

**Order**:
An instruction the player gives to the selected units, such as move or stop. Units can be given orders during a wave, in the build phase and while paused.
_Avoid_: Command (reserved for the simulation's input)

**Barracks**:
The building that trains soldiers. Each one adds to the player's capacity.
_Avoid_: Armoury, garrison (soldiers don't go inside it)

**Capacity**:
How many units the player can have at once: the sum of what every barracks they own adds. Each soldier takes up one, including soldiers still waiting to be trained.
_Avoid_: Supply, population, soldier cap

**Rally point**:
The place a barracks sends each soldier it trains. Without one, a new soldier stands beside the barracks.
_Avoid_: Waypoint, spawn point

**Formation**:
The shape that soldiers given a Move order take where they arrive: a cluster around the point, or a line across their direction of travel. One setting covers the whole army.
_Avoid_: Stance, squad (nothing groups soldiers except the player's selection)

**Elevation**:
The level of the cell a soldier stands on: 0 on the ground, up to 5 on a wall. The higher a soldier's elevation, the further it fires.
_Avoid_: High ground (every level counts, not only the top), height

**Recover**:
A soldier returning to full HP at the end of a wave. Nothing heals a soldier during one.
_Avoid_: Heal, repair (only buildings are repaired)

**Control group**:
A selection of units the player has saved under a number key, to select again with one key.
_Avoid_: Squad, team

### Flow of play

**Run**:
One game, from the first wave until the base is destroyed. A restart begins a new run.
_Avoid_: Game, match, session

**Tuning session**:
One launch of the game from the editor, across however many runs it spans. Its settings are saved to its own file in `data/settings/tuning-sessions/` whenever they change.
_Avoid_: Playtest (a playtest is the human playing, not the file)

**Wave**:
One spawned group of enemies, from pressing "next wave" until the last of them dies.
_Avoid_: Round, level

**Build phase**:
The time between waves.
_Avoid_: Intermission

**Enemies left**:
The enemies in the current wave not yet killed, including those not yet spawned. Between waves, the next wave's size and how many of them are bloaters.

**Wave tail**:
The end of a wave, once Enemies left falls to a set count, which grows with the wave number.
_Avoid_: Endgame, stragglers

### Economy

**Bounty**:
The gold one kill pays before any combo.

**Combo**:
A building's own multiplier on the bounty of its kills, set by how many kills that building made in an unbroken run. It breaks back to nothing when the building goes too long without a kill. Each building has its own; there is no combo for the whole defence.
_Avoid_: Streak, chain, global combo
