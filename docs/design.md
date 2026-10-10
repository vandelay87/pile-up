# pile-up: design

Working title. All numbers are starting values to be tuned during playtesting, and live in a single settings file.

## Project

- Goal: a local prototype to test whether the core loop is fun. A Steam release is considered only if it is.
- Platforms: desktop, macOS and Windows.
- Engine: Godot 4 (standard build), GDScript.
- Built in four prototypes, each adding one system:
  - **v1**: corpse loop
  - **v2**: power, plus a rework of v1 after playtesting (being specified)
  - **v3**: reanimation
  - **v4**: power-ups (to be designed after v3)
- Pace: fast. Enemies die in about two tower hits, and many enemies on screen at once make piles, and then walls, likely to form.

## World and camera

- Isometric view with pan and zoom. The map is roughly 1.5–2 screens wide at default zoom.
- Central base with 200 HP. Enemies attack it at its edge, and the run ends when it is destroyed.
- Each wave spawns from 1–2 random map edges, announced at the start of the wave.
- A fine logical grid sits underneath the isometric rendering. A tower occupies 2×2 cells and a pile occupies 1 cell. Enemies move smoothly, not tile to tile.
- Art: plain coloured shapes. Pile height must read instantly, as stacked blocks that darken with each level.

## Enemies (v1: one type)

- 10 HP, 2 cells/s, drops 1 gold.
- **Swarm spread:** each enemy rolls a pace at spawn (±3% of the base speed), weaves ±30° around its heading over 4 s, and keeps a soft personal space of 0.7 cells, so the swarm spreads across a corridor instead of walking in single file.
- Target: about 1,000 on screen at 60 fps on a MacBook.
- Data-oriented: enemies are plain data rendered in batches, not one scene node each. Separation uses a spatial hash, so each enemy checks only neighbouring cells.

### Routing

- Two flow fields:
  - **Sensible**: piles cost extra in proportion to their slow, and walls and buildings cost their time to break.
  - **Direct**: piles are cheap and walls and buildings are worth breaking.
- Enemies follow the sensible field. When one meets a pile or structure that the sensible field routes around, it rolls once to switch to the direct field: about 5% for piles, 3% for walls and buildings. The result is locked in until the enemy is past that obstacle, then it returns to the sensible field.
- Enemies may change routes during a wave, even if that takes them the long way round. In the wave tail (once Enemies left falls to 10 + 2 × the wave number), an enemy that the sensible field would turn back (a heading change of more than 90°) towards another route switches to the direct field instead, locked in until it is past the obstacle, as with a roll. Changing route while still heading forward stays allowed.

## Body piles

- A killed enemy's body lands on the cell it died on, adding a level to the pile there or starting a new one.
- If that cell cannot take a body (a wall, rock, the base or a building's cell), the body goes to the nearest cell that can, measured from where the enemy died, so it stays on the side the enemy was on. No body is ever lost.
- A body appears on its cell at once, with no landing animation in v2.
- Levels:

  | Level | Effect |
  |-------|--------|
  | 1 | 15% slow |
  | 2 | 30% slow |
  | 3 | 45% slow |
  | 4 | 60% slow |
  | 5 | Wall: impassable, 15 HP |

- A destroyed wall drops back to a level-3 pile.
- **Decay:** at the end of each wave, every pile rolls once to lose one level: about 50% for piles at levels 1–4 and 25% for walls, so walls stand for longer. Each pile rolls on its own, and a pile never loses more than one level per wave end. There is no warning of which piles will decay.
- A destroyed wall drops to level 3 straight away and then rolls at the wave's end like any other pile. A wall that survives its roll keeps its damage into the next wave. A pile that climbs back to a wall comes back at full HP.

## Structures

- Walls, buildings (towers, pylons and repair yards) and the base are all structures, and one rule covers them all.
- An enemy attacks a structure only when it is in the way: it is jammed against it, or its route crosses it. Enemies passing a structure that is not in their way ignore it.
- Every attacker deals 2 damage per second to any structure, with no limit on attackers beyond space around it.
- Enemies killed at a structure die in front of it, so defending a structure builds a pile in front of it.
- A destroyed tower leaves nothing behind: its cells are clear and its gold is lost.

## Power grid

- The base and every building power a square of cells around their footprint, measured from its edge: the base 10 cells, a tower 4, a pylon 10. That square is their **power area**. It ignores piles, walls and rock.
- A building is powered when any of its cells lies in the power area of the base or of another powered building. Power spreads through these overlaps. The base is always powered, and an unpowered building powers nothing.
- The power grid is every cell in a powered area. At the start of a run the base's area alone (24×24 cells) is room for the first three towers.
- A new building's whole footprint must be on the power grid, so the grid grows outwards from its edge.
- Losing a link (a destroyed pylon or tower) can cut off a whole branch. An unpowered tower stops firing, but it is still a structure: it keeps its HP, blocks routes, can be attacked and holds its cells. Power returns at once when a new building links it back up.
- **Pylon**: 1×1, 20 gold, 20 HP, does nothing but power cells. Like a tower, a destroyed pylon leaves nothing behind.
- While a building is being placed, powered cells are tinted. Unpowered buildings are always drawn greyed out with an icon.
- No selling or demolishing in v2, so a stranded building stays until it is destroyed or reconnected.

## Repair yard

- **Repair yard**: 2×2, 80 gold, 60 HP, power area 4 cells. It follows every power rule: it must be built on the power grid, and an unpowered repair yard stops repairing. Like a tower, a destroyed repair yard leaves nothing behind.
- Its **repair area** is a square reaching 8 cells from its edge. A building is inside when any of its cells is.
- It repairs buildings only (towers, pylons and other repair yards), never itself, walls or the base, and only during waves.
- Each repair yard has one **drone**. A repair is a round trip: the drone flies straight to the building over any terrain at 8 cells/s, repairs it at 5 HP/s until it is full, then flies back to the yard before taking its next job. The travel is the cost of far-off repairs. Enemies cannot attack the drone.
- **Auto:** the drone picks the damaged building nearest the yard, lowest HP first on a tie. It prefers a building no other drone is repairing, but doubles up when every damaged building is taken. Drones on the same building add their repair rates.
- **Assignment:** the player can assign one building in the yard's area. Whenever that building is damaged it comes first, once the drone is home from its current trip. Otherwise the drone works on auto. The assignment lasts until the player clears it or the building is destroyed.
- If the building being repaired is destroyed, the drone picks again. If the yard loses power, or the wave's last enemy dies, the drone flies home and stops. If the yard is destroyed, its drone goes with it.
- A building being repaired shows a small steady repair effect. The repair area is tinted while the yard is being placed or selected.

## Selecting buildings

- Clicking a building or the base selects it. Clicking empty ground or pressing Esc clears the selection.
- A selected building shows its range (a tower's fire range, a repair yard's repair area, a pylon's or the base's power area) and a stats panel: HP and max HP, and whether it is powered. A tower adds damage, shots/s, range and its kills this run. A repair yard adds its repair rate, auto or its assignment (with controls to assign a building or clear it) and the HP it has repaired this run. A pylon adds its power area.

## Towers and economy

- One tower type: single-target, aimed at the enemy closest to the base. 5 damage, 3.5 shots/s, range 8 cells, 60 HP, costs 80 gold.
- Towers can only be built on clear cells of the power grid. Building is allowed during waves.
- A tower may cut off every path to the base: enemies then break through the cheapest structure.
- Starting gold: 200.
- **Bounty:** each kill pays 1 gold before any combo.
- **Combo:** the number of kills in the last 2 seconds sets a combo tier: ×2 at 10 kills, ×3 at 20, capped at ×3. Each kill pays its bounty times the current tier, at once, so gold earned mid-burst can be spent during the wave. The combo rises with bursts of killing and falls on its own as they stop; nothing else breaks it. The capped tier keeps late-wave income bounded.
- **HUD:** **Enemies left** counts the current wave's enemies not yet killed, unspawned ones included, so it starts at the wave size and reaches 0 as the wave ends; in the build phase it shows the next wave's size. **Kills** counts the run's kills and is also shown on the game-over screen. The combo readout shows the tier and is hidden at ×1; it pulses and grows on each tier-up and fades as the combo falls, and the gold readout flashes on a multiplied payout.

## Waves

- Endless. The next wave starts when the player presses "next wave".
- Wave 1 has 20 enemies. Each wave has about 30% more enemies and 5% more enemy HP than the last, so wave 10 is roughly 210 enemies and wave 20 roughly 2,900.
- Enemies spawn in bursts of 16, each on a random cell along the spawn edge, at an average of 10 per second.

## v1 fun test

After about 10 runs:

1. Does the player deliberately place towers to shape where piles form? (This is the most important test.)
2. Do walls change plans in an enjoyable way?
3. Do piles shrinking between waves create real choices?
4. Do 1,000 enemies flowing around piles look and feel good?

If 1 and 2 fail, the pile rules get reworked before starting reanimation. Playtesting led to that rework, which is v2.

## v3: reanimation

- Unlocked by building an **altar** (100 gold) in one of a few build slots touching the base. Each altar raises one pile at a time.
- Raising costs 1.5 s and 10 gold per body, during waves only, and produces one minion per body. The pile is used up.
- A pile being raised is attackable, with 5 HP per body. Enemies within 2 cells target it about 30% of the time. If it is destroyed, the bodies and the gold are lost.
- Minions have the same stats as enemies and are controlled with one rally point per group.

### Combat between minions and enemies

- **Enemies**:
  - An enemy touching a minion rolls about 20% to stop and fight.
  - It always fights when minions block its path or when a minion attacks it.
  - Enemies never chase fleeing minions. Once contact breaks, they return to their route.
- **Minions**:
  - When a group is given a move order, each minion that is in a fight rolls 50% to break off. The rest stay stuck until their opponent dies.
  - Dead minions leave bodies, like everything else.
  - Survivors stay standing through the build phase and can be moved. When "next wave" is pressed, each group collapses into a pile where it stands, which lets the player build corpse terrain on purpose.

## Finished game direction

Not built in the prototypes, but decisions should leave room for it.

- **Levels:** three levels, each with its own look and possibly a twist. A level is won by reaching a set wave, which unlocks the next.
- **Level 1** is a narrow map that funnels the swarm a couple of ways, so piles and walls form readily.
- **Map variety:** maps range from narrow to more open. Piles and walls come from the sheer number of enemies in a wave, not from bodies being drawn together.
- **The prototypes stay endless,** with no wave goal.
- **Seeds and procedurally generated levels** are a possible future addition, out of scope for the prototypes. Maps are already stored as validated data, so a generator could produce them.

## Later ideas

- Enemy types: brutes that always break walls, enemies that seek out buildings even when they are not in the way, enemies that chase.
- A splash/area tower.
- Power-ups (v4), including interactions with piles (for example, flame setting piles alight).
- Meta-progression between runs.
- A generator that powers an area cut off from the base's power grid.
- Selling or demolishing buildings.
- Building upgrades, such as more drones per repair yard (with power-ups in v4).
- A ranked queue of assignments for a repair yard.
- Larger piles producing a single brute minion.
- A landing animation for bodies, with the final art.
- Combo juice with the final art and audio: sound, effects and floating numbers.
