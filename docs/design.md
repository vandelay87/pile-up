# pile-up: design

Working title. All numbers are starting values to be tuned during playtesting, and live in a single settings file.

## Project

- Goal: a local prototype to test whether the core loop is fun. A Steam release is considered only if it is.
- Platforms: desktop, macOS and Windows.
- Engine: Godot 4 (standard build), GDScript.
- Built in five prototypes, each adding one system:
  - **v1**: corpse loop
  - **v2**: power, plus a rework of v1 after playtesting
  - **v3**: pressure: overflow, the grinder, the bloater, per-building combos and repair as a trade-off, after the v2 playtest showed a late game that could not be broken (specified in `docs/specs/v3.md`)
  - **v4**: reanimation, after a performance pass towards the 1,000-enemy target
  - **v5**: power-ups (to be designed after v4)
- Pace: fast. Enemies die in about two tower hits, and many enemies on screen at once make piles, and then walls, likely to form.

## World and camera

- Isometric view with pan and zoom. The map is roughly 1.5–2 screens wide at default zoom.
- Central base with 200 HP. Enemies attack it at its edge, and the run ends when it is destroyed.
- Each wave spawns from 1–2 random map edges, announced at the start of the wave.
- From the pressure prototype, the map's routes **flare out** towards the spawn edges: wide mouths that funnel down towards the base, so a big wave arrives spread out and packs tighter as it nears the base. Small pockets beside the chokepoints give an overflow room to spill into.
- **No-build margin:** nothing can be built within 6 cells of a spawn edge. Enemies still walk there, but the power grid can never reach the spawn mouths. The margin is tinted while a building is being placed.
- A fine logical grid sits underneath the isometric rendering. A tower occupies 2×2 cells and a pile occupies 1 cell. Enemies move smoothly, not tile to tile.
- Art: plain coloured shapes. Pile height must read instantly, as stacked blocks that darken with each level.

## Enemies (v1: one type)

- 10 HP, 2 cells/s, drops 1 gold.
- **Swarm spread:** each enemy rolls a pace at spawn (±3% of the base speed), weaves ±30° around its heading over 4 s, and keeps a soft personal space of 0.7 cells, so the swarm spreads across a corridor instead of walking in single file.
- Target: about 1,000 on screen at 60 fps on a MacBook. v3 doesn't meet it yet: on an M5 release build, 1,000 dense enemies average about 16 ms a frame, but the slowest frames take 22–24 ms, from the simulation. v3 was accepted as a prototype as it is, and v4 starts with a performance pass ([#150](https://github.com/vandelay87/pile-up/issues/150)).
- Data-oriented: enemies are plain data rendered in batches, not one scene node each. Separation uses a spatial hash, so each enemy checks only neighbouring cells.

### Routing

- Two flow fields:
  - **Sensible**: piles cost extra in proportion to their slow, and walls and buildings cost their time to break.
  - **Direct**: piles are cheap and walls and buildings are worth breaking.
- Enemies follow the sensible field. When one meets a pile or structure that the sensible field routes around, it rolls once to switch to the direct field: about 5% for piles, 3% for walls and buildings. The result is locked in until the enemy is past that obstacle, then it returns to the sensible field.
- Enemies may change routes during a wave, even if that takes them the long way round. In the wave tail (once Enemies left falls to 10 + 2 × the wave number), an enemy that the sensible field would turn back (a heading change of more than 90°) towards another route switches to the direct field instead, locked in until it is past the obstacle, as with a roll. Changing route while still heading forward stays allowed.

### Pressure and overflow

From v3, a crowd that stalls against a defence builds up until it tumbles over, so a big enough wave always threatens to spill.

- **Crush:** the stalled crowd against one barrier: a connected stretch of walls and buildings. Enemies within 3 cells of it count. Piles at levels 1–4 don't stop enemies, so a crowd can't crush against them, and the base never has a crush. A crowd at each end of one long wall shares the same crush.
- **Pressure:** each crush has a gauge, drawn above the middle of its stalled enemies. It fills while enemies near the obstacle want to move but make no progress, faster the more of them there are, and leaks at a steady rate, so a passing clump drains away and early waves rarely fill it. A crush starts above one reading and ends below a lower one, so the gauge doesn't flicker.
- **Overflow tiers:** the gauge has three segments: a **trickle** (one enemy now and then), a **stream** (a steady line) and a **surge** (the front ranks pouring over together). Each enemy that tumbles over takes something off the gauge, so a trickle can settle and a surge lasts only while the wave keeps feeding the crush.
- **Who tumbles:** stalled enemies right against the obstacle that aren't attacking it, taken from anywhere along the front, so overflow comes over as a broad front rather than one line. Attackers keep attacking; they tumble only when every enemy at the front is attacking.
- **The tumble:** an enemy tumbles straight over the piece of wall or building it is touching, on the side facing most towards the base, to the first free, uncrowded cell beyond it, then goes back to the sensible field. If nothing it touches faces forwards, it follows the direct field over instead. It falls fast, quicker than walking, is drawn raised, ignores collision with the obstacle and the crowd and isn't slowed by piles, and can be shot and killed on the way; its body falls back the way it came, landing where its tumble started, and so does the body of one killed within a second of landing, so the overflow's dead build a ramp behind it rather than a wall in front. There is no limit on how far a tumble crosses: a thick block of buildings still resists, because a long tumble keeps the enemy exposed to every tower in range. If a tumble reaches the base with no free cell, the enemy stops beside the base and attacks it.
- **What it crosses:** nothing changes. Overflow goes over a defence; attacks still wear it down.
- Towers target tumbling enemies like any other enemy, and route rolls and wave-tail push-through stay as they are.
- **v3 numbers:** an enemy within the 3-cell band is stalled below 25% of its walking progress. The gauge fills 1.5 per stalled enemy per second and leaks 40 per second, so about 27 stalled enemies only hold it level, and a gauge drains within seconds once its crowd thins (raised from 0.5 and 5 after the tumbling playtest, which left a thinned crush lingering at trickle or stream). A crush starts above 10 and ends below 4. Trickle from 20, stream from 50, surge from 90, and the gauge tops out at 120. The tiers send 0.5, 3 and 15 enemies over per second, and each enemy that tumbles takes 2 off the gauge. A tumble moves at 180% of walking speed, and a landing cell is free while it holds fewer than 6 enemies.

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
- **Decay:** at the end of each wave, every pile rolls once to lose one level: one chance for piles at levels 1–4 and a lower one for walls, so walls stand for longer. Each pile rolls on its own, and a pile never loses more than one level per wave end. There is no warning of which piles will decay. **v3 numbers:** both chances are 0, so decay is off: blasts now erase piles and walls, and the v3 tuning playtest kept the field without decay (v2 was 50% for piles and 25% for walls).
- A destroyed wall drops to level 3 straight away and then rolls at the wave's end like any other pile. A wall that survives its roll keeps its damage into the next wave. A pile that climbs back to a wall comes back at full HP.

## Structures

- Walls, buildings (towers, pylons, repair yards and grinders) and the base are all structures, and one rule covers them all.
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
- **Pylon**: 1×1, 30 gold, 20 HP, does nothing but power cells. Like a tower, a destroyed pylon leaves nothing behind.
- While a building is being placed, powered cells are tinted. Unpowered buildings are always drawn greyed out with an icon.
- No selling or demolishing in v2, so a stranded building stays until it is destroyed or reconnected.

## Repair yard

- **Repair yard**: 2×2, 120 gold, 60 HP, power area 4 cells. It follows every power rule: it must be built on the power grid, and an unpowered repair yard stops repairing. Like a tower, a destroyed repair yard leaves nothing behind.
- Its **repair area** is a square reaching 8 cells from its edge. A building is inside when any of its cells is.
- It repairs buildings only (towers, pylons, grinders and other repair yards), never itself, walls or the base, and only during waves.
- Each repair yard has one **drone**. A repair is a round trip: the drone flies straight to the building over any terrain at 8 cells/s, repairs it at 5 HP/s until it is full, then flies back to the yard before taking its next job. The travel is the cost of far-off repairs. Enemies cannot attack the drone.
- **Repair threshold:** each yard has a setting of 25, 50, 75 or 100% of max HP, 50% for a new yard and changed from its details. Its drone only picks a building whose HP is below that share, its assignment included, and then repairs it to full. At 100% any damage counts.
- **Auto:** the drone picks the building below the threshold nearest the yard, lowest HP first on a tie. It prefers a building no other drone is repairing, but doubles up when every damaged building is taken. Drones on the same building add their repair rates.
- **Assignment:** the player can assign one building in the yard's area. Whenever that building is below the threshold it comes first, once the drone is home from its current trip. Otherwise the drone works on auto. The assignment lasts until the player clears it or the building is destroyed.
- If the building being repaired is destroyed, the drone picks again. If the yard loses power, or the wave's last enemy dies, the drone flies home and stops. If the yard is destroyed, its drone goes with it.
- **Under repair:** while a drone is repairing a building (not while it flies there), the building stops working as if unpowered: a tower holds fire and keeps its cooldown, ready the moment the drone lifts off; a grinder stops hurting; a repair yard's own drone flies home and stops. A pylon is the exception and keeps powering, so a repair never cuts power. A building under repair still blocks, is attacked and is climbed. Repair is a trade-off: the building is pulled out of the fight to save it.
- A building under repair shows a small steady repair effect. It is not greyed out, which stays the mark of an unpowered building. The repair area is tinted while the yard is being placed or selected.

## Grinder

From v3, a building that hurts enemies by touch, so the player can plan for a crush and its overflow.

- **Grinder**: 2×2, power area 2 cells. It follows every building rule: it must be built on the power grid and stops hurting while unpowered, it blocks routes, enemies attack it, repair yards repair it, it joins a barrier, and a destroyed grinder leaves nothing behind.
- **Contact damage:** every enemy touching it, within a small band of its footprint, takes a flat damage per second: walkers brushing past, the crush pressed against it and enemies attacking it alike. Its total damage grows with how many enemies touch it, so it barely troubles a thin stream and grinds a crush down. An enemy touching two grinders takes damage from both.
- **Overflow:** enemies tumble over a grinder like any other building, and take one second's worth of its damage for each of its cells they cross, so a thick block of grinders is a gauntlet.
- **Role:** a wall that bites, not a tower. It costs somewhat less than a tower, has more HP than one, and kills a lone enemy slowly. Wrapping buildings in grinders is allowed; its price is the limit.
- Its kills build its own combo like a tower's, kills on tumbling enemies included.
- Bodies of enemies it kills land by the normal rule, so piles build up against it, and a wall there keeps enemies off it until that wall breaks or decays.
- **v3 numbers:** 90 gold, 100 HP, 3 damage per second to each enemy touching it. Touching means close enough to attack it, so its band is an attacker's reach and needs no number of its own. A lone enemy takes about 3 s to die at wave 1 and about 7 s at wave 15, and an enemy tumbling over one grinder takes 6.

## Bloater

From v3, a second enemy type that blows up, so a crowd can be broken from inside and a defence from outside. Where it pops decides which.

- **Bloater**: 3× a normal enemy's HP (30) and 0.8× its speed (1.6 cells/s), so it drifts back into the crowd behind it. Bounty 2 gold. It grows with the waves' HP like any enemy. It is drawn in its own colour, 1.5× the size of a normal enemy, and pulses faster and faster while its fuse burns.
- **Fuse:** when a bloater reaches a structure in its way (the moment a normal enemy would start attacking), it lights a 1 s fuse and blows up when it runs out. It never attacks. Killing it during the fuse still blows it up there.
- **Blast:** whenever a bloater dies, by any cause, it blows up: every enemy within 2 cells of its centre dies, leaving no body, every building and the base within it takes 30 damage once (half a tower's HP), and every pile and wall within it is erased, leaving nothing. The edge is hard: inside takes the full effect, outside takes nothing. A bloater leaves no body either, so a blast leaves a clear crater.
- **Chains:** a blast that kills another bloater sets it off too.
- **Grinders** hurt a bloater like any enemy, so one that dies against a grinder blows up there and damages it.
- **Crush:** blasts need no special rule. The enemies they kill leave the crush smaller, and a wall they erase is a hole the crowd walks through, not an overflow.
- **Overflow:** a bloater with a lit fuse is not attacking, so it can be picked to tumble like any enemy at the front. Tumbling puts its fuse out, and it lights again at the next structure in its way after it lands, so an overflow can carry bloaters into the defence. A bloater killed mid-tumble blows up where it is, on top of the wall or building it is crossing.
- **Combos and bounty:** a building that kills a bloater gets every kill its blast makes, chained blasts included: each adds to that building's combo and pays its bounty × the building's tier. A bloater that blows itself up pays no bounty of its own, and its blast kills pay ×1.
- Which waves have bloaters, and how many, is under Waves.

## Selecting buildings

- Clicking a building or the base selects it. Clicking empty ground or pressing Esc clears the selection.
- A selected building shows its range (a tower's fire range, a repair yard's repair area, a pylon's or the base's power area) and a stats panel: HP and max HP, and a **status**. The status is one word: Unpowered, else Under repair, else what it is doing (a tower Firing or Idle, a grinder Grinding or Idle, a repair yard Repairing or Idle, a pylon Powering). The base has no status. A tower adds damage, shots/s, range, its kills this run and its targeting toggle. A repair yard adds its repair rate, auto or its assignment (with controls to assign a building or clear it), its repair threshold (with a control to change it) and the HP it has repaired this run. A pylon adds its power area. A grinder adds its damage per second, the enemies touching it now and its kills this run.

## Towers and economy

- One tower type: single-target, aimed at the enemy closest to the base. From v3, a tower prefers a bloater in its range by default, so long reach ahead of the walls pops bloaters in the open; each tower has a toggle in its details to aim at the closest enemy to the base instead. 5 damage, 3.5 shots/s, range 8 cells, 60 HP, costs 120 gold.
- Towers can only be built on clear cells of the power grid. Building is allowed during waves.
- A tower may cut off every path to the base: enemies then break through the cheapest structure.
- Starting gold: 300, 2.5 towers' worth. The v3 tuning playtest raised it and every building's cost by half (from 200 gold, and 80 for a tower), so the opening is unchanged and the mid and late waves are tighter.
- **Bounty:** each kill pays 1 gold before any combo.
- **Combo:** each building has its own combo; there is none for the whole defence. The building that lands the killing blow gets the kill, and any building that damages enemies can build a combo. Each kill adds 1 to the building's count and restarts its timer; if the timer runs out with no kill, the combo breaks back to ×1. The count sets the building's tier, capped. Each kill pays its bounty times the killing building's tier, at once, the kill that crosses a threshold already paying the new tier, so gold earned mid-burst can be spent during the wave. Kills with no building behind them pay ×1. A destroyed building loses its combo and its rebuild starts at ×1; damage to a building or the base does not break one. A high combo needs a dense crowd in front of one building, so it rewards letting pressure build, at the risk of an overflow. **v3 numbers:** a 2 s timer, ×2 from 10 kills, ×3 from 25, capped at ×3. A busy tower kills often enough to hold its timer while a crowd feeds it, and the cap stays at ×3 so the combo doesn't bring back v2's gold surplus.
- **HUD:** **Enemies left** counts the current wave's enemies not yet killed, unspawned ones included, so it starts at the wave size and reaches 0 as the wave ends; in the build phase it shows the next wave's size, followed by its bloater count when it has any (for example, "120 enemies · 3 bloaters"). **Kills** counts the run's kills and is also shown on the game-over screen. A building's combo shows above it as a **ring**, hidden at ×1: its tier in the middle, an outer arc filling towards the next tier, and an inner arc for its timer running down. A kill pulses the ring, a tier-up sends a ring outwards, and a break scatters it. The ring stays the same size on screen at any zoom, in shades of gold so it isn't mistaken for the pressure gauge. The selected building's details show the same ring, larger, with its tier and count, the next tier's threshold, the time left on its timer and its best combo this run. The final art may restyle the ring but keeps what it shows. There is no combo readout for the whole defence. The gold readout flashes on a multiplied payout.

## Waves

- Endless. The next wave starts when the player presses "next wave".
- Wave 1 has 20 enemies. Each wave has 25% more enemies and 5% more enemy HP than the last, so wave 10 is roughly 150 enemies, wave 15 roughly 455 and wave 20 roughly 1,390. (v2 grew 30% a wave; v3 lowers it to cut the gold surplus and keep wave 20 nearer the on-screen target.)
- Enemies spawn in bursts of 16, each on a random cell along the spawn edge, at an average of 10 per second. v3 keeps these on the flared map, where the wider mouths already spread the bursts out.
- **Bloaters** (from v3) appear from wave 5. They take the place of normal enemies, so the wave size is unchanged. Their count steps up slowly whatever the wave's size: 1, then one more every few waves, and each wave rolls once for one fewer or one more, so an early wave sometimes has none. The roll is fixed per run and wave, so the build phase's count always matches the wave. Each bloater takes a random place among the wave's bursts, mixed in with normal enemies; there are no bursts of only bloaters. **v3 numbers:** one more every 6 waves, so a base of 1 for waves 5–10, 2 for 11–16, 3 for 17–22 and 4 from 23; a 25% chance of one fewer and a 10% chance of one more. (Replaced a share of the wave, 2% rising to 5%, after the v3 tuning playtest: with 25% wave growth it gave 23 bloaters at wave 15 and 69 at wave 20.)

## v1 fun test

After about 10 runs:

1. Does the player deliberately place towers to shape where piles form? (This is the most important test.)
2. Do walls change plans in an enjoyable way?
3. Do piles shrinking between waves create real choices?
4. Do 1,000 enemies flowing around piles look and feel good?

If 1 and 2 fail, the pile rules get reworked before starting reanimation. Playtesting led to that rework, which is v2.

## v4: reanimation

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
- Power-ups (v5), including interactions with piles (for example, flame setting piles alight).
- Meta-progression between runs.
- A generator that powers an area cut off from the base's power grid.
- Selling or demolishing buildings.
- Building upgrades, such as more drones per repair yard (with power-ups in v5).
- A ranked queue of assignments for a repair yard.
- Larger piles producing a single brute minion.
- A landing animation for bodies, with the final art.
- Combo juice with the final art and audio: sound, effects and floating numbers.
- Special waves: a wave that, on a small chance, breaks the usual pattern, for example one with an abnormal number of bloaters. Further on, waves that mutate into a random mix of enemy types.
- Wildcards: rule changes for the rest of a run, such as towers firing twice as fast or buildings with more HP, and rarer, wilder ones, such as every enemy having a small chance to blow up like a bloater. How the player gets one is open: perhaps by building a special building, perhaps at random. They sit close to power-ups (v5), so they may end up as one system.
