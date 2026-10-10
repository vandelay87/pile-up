# pile-up: design

Working title. All numbers are starting values to be tuned during playtesting, and live in a single settings file.

## Project

- Goal: a local prototype to test whether the core loop is fun. A Steam release is considered only if it is.
- Platforms: desktop, macOS and Windows.
- Engine: Godot 4 (standard build), GDScript.
- Built in three prototypes, each adding one system:
  - **v1**: corpse loop
  - **v2**: reanimation
  - **v3**: power-ups (to be designed after v2)
- Pace: fast. Enemies die in about two tower hits, and many enemies on screen at once make piles, and then walls, likely to form.

## World and camera

- Isometric view with pan and zoom. The map is roughly 1.5–2 screens wide at default zoom.
- Central base with 20 lives. An enemy that reaches it removes 1 life and dies.
- Each wave spawns from 1–2 random map edges, announced at the start of the wave.
- A fine logical grid sits underneath the isometric rendering. A tower occupies 2×2 cells and a pile occupies 1 cell. Enemies move smoothly, not tile to tile.
- Art: plain coloured shapes. Pile height must read instantly, as stacked blocks that darken with each level.

## Enemies (v1: one type)

- 10 HP, 1.5 cells/s, drops 1 gold.
- Target: about 1,000 on screen at 60 fps on a MacBook.
- Data-oriented: enemies are plain data rendered in batches, not one scene node each. Separation uses a spatial hash, so each enemy checks only neighbouring cells.

### Routing

- Two flow fields:
  - **Sensible**: piles cost extra in proportion to their slow, and walls cost their time to break.
  - **Direct**: piles are cheap and walls are worth breaking.
- Enemies follow the sensible field. When one meets a pile or wall that the sensible field routes around, it rolls once to switch to the direct field: about 5% for piles, 3% for walls. The result is locked in until the enemy is past that obstacle, then it returns to the sensible field.

## Body piles

- A killed enemy's body joins the tallest pile within 1 cell; otherwise it starts a new pile on its cell.
- A body that would land on a tower cell moves to the nearest free cell.
- Levels:

  | Level | Effect |
  |-------|--------|
  | 1 | 15% slow |
  | 2 | 30% slow |
  | 3 | 45% slow |
  | 4 | 60% slow |
  | 5 | Wall: impassable, 30 HP |

- Enemies attacking a wall deal 1 damage per second, with no limit on attackers beyond space around it.
- Bodies of enemies killed at a wall spill into the nearest non-wall cell, so defending a wall thickens it.
- A destroyed wall drops back to a level-3 pile.
- Every pile loses one level at the end of each wave.

## Towers and economy

- One tower type: single-target, aimed at the enemy closest to the base. 3 damage, 2 shots/s, range 8 cells, costs 50 gold.
- Towers can only be built on clear cells. Building is allowed during waves.
- Starting gold: 150.

## Waves

- Endless. The next wave starts when the player presses "next wave".
- Wave 1 has 20 enemies. Each wave has about 20% more enemies and 5% more enemy HP than the last, so wave 20 is roughly 700 enemies.

## v1 fun test

After about 10 runs:

1. Does the player deliberately place towers to shape where piles form? (This is the most important test.)
2. Do walls change plans in an enjoyable way?
3. Do piles shrinking between waves create real choices?
4. Do 1,000 enemies flowing around piles look and feel good?

If 1 and 2 fail, the pile rules get reworked before starting v2.

## v2: reanimation

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
- **The prototypes stay endless,** with no wave goal.
- **Seeds and procedurally generated levels** are a possible future addition, out of scope for the prototypes. Maps are already stored as validated data, so a generator could produce them.

## Later ideas

- Enemy types: brutes that always break walls, enemies that attack towers, enemies that chase.
- A splash/area tower.
- Power-ups (v3), including interactions with piles (for example, flame setting piles alight).
- Meta-progression between runs.
- Larger piles producing a single brute minion.
