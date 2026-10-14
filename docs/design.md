# pile-up: design

Working title. All numbers are starting values to be tuned during playtesting, and live in a single settings file.

## Project

- Goal: a local prototype to test whether the core loop is fun. A Steam release is considered only if it is.
- Platforms: desktop, macOS and Windows.
- Engine: Godot 4 (standard build), GDScript.
- Built in a series of prototypes, each adding one system:
  - **v1**: corpse loop
  - **v2**: power, plus a rework of v1 after playtesting
  - **v3**: pressure: overflow, the grinder, the bloater, per-building combos and repair as a trade-off, after the v2 playtest showed a late game that could not be broken (specified in `docs/specs/v3.md`)
  - **v4**: units: the soldier, trained in the barracks and directed by the player (lite RTS, never an RTS), with elevation tying soldiers to piles; it opens with a performance pass towards the 1,000-enemy target (specified in `docs/specs/v4.md`)
  - Later prototypes are not set in stone: v5 could be anything. Power-ups and wildcards come when they are ready to be fleshed out
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
- Target: about 1,000 on screen at 60 fps on a MacBook. v3 doesn't meet it yet: on an M5 release build, 1,000 dense enemies average about 16 ms a frame, but the slowest frames take 22–24 ms, from the simulation. v3 was accepted as a prototype as it is, and v4 opens with a performance pass aiming for a tick p99 of about 12 ms at 1,000, which leaves about 2 ms of tick for units (`docs/specs/v4.md`, section 5).
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
- From v4, a dead soldier leaves a body by the same rule, and once it lands it is a body like any other (see Death and recovery under Units).
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

- Walls, buildings (towers, pylons, repair yards, grinders and, from v4, barracks) and the base are all structures, and one rule covers them all.
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
- **Fuse:** when a bloater reaches a structure, or from v4 a soldier, in its way (the moment a normal enemy would start attacking), it lights a 1 s fuse and blows up when it runs out. It never attacks. Killing it during the fuse still blows it up there.
- **Blast:** whenever a bloater dies, by any cause, it blows up: every enemy within 2 cells of its centre dies, leaving no body, every building and the base within it takes 30 damage once (half a tower's HP), every soldier within it takes the blast's damage once (from v4, under Fighting), and every pile and wall within it is erased, leaving nothing. The edge is hard: inside takes the full effect, outside takes nothing. A bloater leaves no body either, so a blast leaves a clear crater.
- **Chains:** a blast that kills another bloater sets it off too.
- **Grinders** hurt a bloater like any enemy, so one that dies against a grinder blows up there and damages it.
- **Crush:** blasts need no special rule. The enemies they kill leave the crush smaller, and a wall they erase is a hole the crowd walks through, not an overflow.
- **Overflow:** a bloater with a lit fuse is not attacking, so it can be picked to tumble like any enemy at the front. Tumbling puts its fuse out, and it lights again at the next structure in its way after it lands, so an overflow can carry bloaters into the defence. A bloater killed mid-tumble blows up where it is, on top of the wall or building it is crossing.
- **Combos and bounty:** a building, or from v4 a soldier, that kills a bloater gets every kill its blast makes, chained blasts included: each adds to its combo and pays its bounty × its tier. A bloater that blows itself up pays no bounty of its own, and its blast kills pay ×1.
- Which waves have bloaters, and how many, is under Waves.

## Selecting buildings

- Clicking a building or the base selects it. Clicking empty ground or pressing Esc clears the selection.
- A selected building shows its range (a tower's fire range, a repair yard's repair area, a pylon's or the base's power area) and a stats panel: HP and max HP, and a **status**. The status is one word: Unpowered, else Under repair, else what it is doing (a tower Firing or Idle, a grinder Grinding or Idle, a repair yard Repairing or Idle, a pylon Powering, a barracks Training or Idle). The base has no status. A tower adds damage, shots/s, range, its kills this run and its targeting toggle. A repair yard adds its repair rate, auto or its assignment (with controls to assign a building or clear it), its repair threshold (with a control to change it) and the HP it has repaired this run. A pylon adds its power area. A grinder adds its damage per second, the enemies touching it now and its kills this run.

## Units (v4)

- **Soldier:** v4's one unit. It shoots enemies in range like a tower and only moves when ordered; it never chases. Each soldier has the towers' targeting toggle, Bloaters first (the default for a newly trained soldier) or Closest to base.
- **Selecting:** clicking a soldier selects it alone. Dragging a box selects every soldier inside it, never buildings. Shift-click or shift-drag adds soldiers to the selection or takes them out. Buildings and soldiers are never selected together: clicking a building clears the selected soldiers. Esc or a click on empty ground clears the selection.
- **Orders:** right-click on the ground, or on an enemy, moves the selected soldiers there; **Stop** cancels the move. There is no hold, attack-move, focus fire or waypoint queue. Orders can be given during a wave and in the build phase.
- **Targeting a selection:** the toggle sets every selected soldier at once, and shows Mixed while their modes differ (see The unit in the HUD).
- **Control groups:** Ctrl+1–9 saves the selected soldiers as a group, 1–9 selects it again, and pressing the number twice centres the camera on it.
- **Feedback:** a selected soldier's marker is drawn on top of everything, so piles and the crowd never hide it; the final art sets its shape. A Move order flashes a marker where it lands. Tested in the control prototype ([#161](https://github.com/vandelay87/pile-up/issues/161)).
- **Camera with units:** a left-drag is the selection box, so it no longer pans the camera. Panning is a middle-drag, a two-finger trackpad drag or the arrow keys.
- **Pause:** Space pauses the game. Pausing stops the clock and nothing else: the player can still select, give orders, build and change settings, and orders play out on resume. The pause is what keeps v4 a lite RTS.

### Moving units

- **Among enemies:** soldiers and enemies push each other softly, and a soldier is much heavier than an enemy, so a thin stream barely moves it. A standing soldier that is pushed off its spot walks back to it as soon as it can, so standing still means holding that spot. A soldier under a Move order shoulders through the crowd, slowed by how packed it is. A soldier line holds against a trickle, bends under a stream and gives way to a surge: a speed bump and a firing position, never a wall. **v4 numbers:** a soldier walks 2.5 cells/s, a little faster than an enemy, and has mass 5 to an enemy's 1, so in an overlap it gives way a sixth as much. A pushed soldier walks back to its spot at its normal speed; there is no separate push-back speed.
- Soldiers are never part of the flow fields, so they never cause a field repair, and never part of a barrier, so enemies held up by them form no crush and fill no pressure gauge. A tumbling enemy ignores soldiers as it ignores the crowd.
- **Among soldiers:** soldiers keep the same soft personal space as enemies (0.7 cells) from each other, so moving soldiers slide past one another and never stack, and they don't shove a standing soldier off its spot.
- **Piles:** levels 1–4 slow a soldier exactly as they slow an enemy. A pile that grows under a standing soldier lifts it on top; a blast that erases the pile drops it to the ground.
- **Walls:** a soldier can climb onto a wall and over it, at a heavier slow than a level-4 pile (75%), and can stand on top. A wall that forms under a soldier lifts it on top, and a wall destroyed under one drops to level 3 with the soldier still on it. Enemies still need an overflow to cross a wall.
- **Solid:** buildings, rock and the base. Soldiers route around them and never stand on them. The no-build margin is open ground to soldiers.
- **Pathing:** each Move order, a rally point's included, plans the quickest path to its target over the grid: piles cost their slow, walls cost the climb, and buildings and rock can't be crossed. The path is planned again only when a cell on it changes. A target a soldier can't stand on or reach becomes the nearest reachable spot. The enemies' flow fields lead only to the base and are never used. This fixes the control prototype's soldiers getting stuck behind a wall's corner ([#161](https://github.com/vandelay87/pile-up/issues/161)).
- **Formation:** the command card for selected soldiers has a Formation setting, **Cluster** (the default) or **Line**. It is one setting for the whole army, kept until changed, and each Move order takes it as it stands when the order is given: soldiers already sent keep their shape, so one group can be sent in a line and the next in a cluster. Cluster packs slots around the clicked point, about one soldier per cell and skipping cells a soldier can't stand on, and each soldier takes the nearest free slot. Line centres on the clicked point, set across the direction of travel (from the selection's centre to the click), one soldier per cell, shoulder to shoulder, so soldiers sent at a breach line up across it. Each soldier walks its own path to its slot; the shape forms on arrival, not on the march.

### Fighting

- **Firing:** a soldier fires by the tower's rules: one target at a time, instant hits, no line of sight, a cooldown, and the targeting toggle. Its damage, fire rate and range are its own settings, aiming for a shorter range than a tower's and far less damage per second, so one soldier is cheap and weak and a handful hold a breach. **v4 numbers:** 2 damage, 2 shots/s (4 damage per second, under a quarter of a tower's) and range 4 cells, half a tower's.
- **On the move:** a soldier under a Move order fires at any enemy in range, and walks at half speed while it does. With nothing in range it walks at full speed, so crossing open ground is quick and pushing through a crowd is slow but fought the whole way.
- **Enemies attack soldiers** by the structure rule: only when a soldier is in their way, jammed against it and held up, at the same 2 damage per second. Enemies never leave their route to go for a soldier.
- **Bloaters:** a soldier in a bloater's way lights its fuse, just as a structure does. Its blast hits every soldier inside it once, and two blasts kill a soldier: a soldier's HP sits above one blast's damage and at or below two. **v4 numbers:** 45 HP against a blast's 30, so a soldier survives one blast with 15 HP left.
- **Grinders** never hurt soldiers. **Tumbling enemies** don't count soldiers towards a full landing cell, and one that lands against a soldier attacks it like any enemy in its way. A tumble over a wall a soldier stands on knocks the soldier off (see Elevation). Soldiers shoot tumbling enemies like any other.
- **Bounty and combo:** a soldier's kills pay bounty and build a combo of its own, by every building rule (see Towers and economy): the soldier that lands the killing blow gets the kill, it has its own ring above it, hidden at ×1, and moving never breaks a combo, only its timer does. A soldier that kills a bloater gets every kill its blast makes, as a building does.
- **No upkeep:** a soldier costs its training price and nothing more while it is fielded. Training price, capacity and the gold lost with a dead soldier hold the army down; upkeep comes back only if playtests show soldiers piling up gold.
- **Building on soldiers:** placing a building over soldiers pushes them to the nearest free cell, by the same rule that places a new soldier.

### Elevation

- **Elevation:** a soldier's elevation is the level of the cell it stands on: 0 on the ground, 1–4 on a pile, 5 on a wall. Buildings are solid to soldiers, so they give none. It changes whenever the soldier's cell does: walking, a pile growing under it, a blast erasing the pile (back to 0), or a wall destroyed under it (down to 3).
- **Range bonus:** each level of elevation adds the same extra fire range, so a wall gives five steps' worth. It depends only on the soldier's own elevation, never the target's, so a soldier has one range at a time. It is the only bonus: damage and fire rate stay the same, and there is still no line of sight. **v4 number:** 0.5 cells per level, so range 5 on a level-2 pile and 6.5 on a wall, still short of a tower's 8. It aims for piles worth standing on without making them a must.
- **Walking over piles:** range follows elevation as the soldier moves or is lifted. A step down that leaves the current target out of range drops it, and the soldier picks again by its targeting toggle, as a tower does when an enemy walks out of range.
- **Reading it:** a pile's stacked blocks show how high a soldier stands, and selected soldiers show their range, as a selected tower does, each at its current elevation (see The unit in the HUD). There is no other marker.
- **Safe on a wall:** enemies on the ground can't attack a soldier standing on a wall, since an enemy jammed against the wall is held up by the wall, not the soldier. Blasts still hit it, and a wall destroyed under it drops it to level 3.
- **Knock-off:** a tumble over the wall cell a soldier stands on knocks that soldier down to the landing side, onto the nearest free ground cell. It lands at elevation 0 among the enemies that came over, in their way, and a standing soldier climbs back to its spot if it survives. Only the soldier on the crossed cell is knocked off; soldiers further along the wall are not.
- **Enemies** get nothing from height: they only attack what is in their way.

### Death and recovery

- **Recovery:** every living soldier recovers to full HP the moment the wave's last enemy dies, when repair yard drones fly home. Nothing heals a soldier during a wave, so the build phase always starts with the army at full HP, and a newly trained soldier starts at full HP. Repair stays for buildings only.
- **Death:** a soldier at 0 HP is lost. Its gold and its combo are gone, its place in capacity is freed at once, and nothing replaces it: the player trains another by hand. It drops out of the selection and every control group.
- **Body:** a dead soldier leaves one body by the body pile rule, landing on its cell or the nearest one that can take it, and adding a level. Once it lands it is a body like any other, with nothing to tell it from an enemy's. A soldier killed by a blast leaves no body, as an enemy doesn't, so the crater stays clear.
- **Feedback:** a brief death effect where the soldier falls; the final art sets its look. There is no alert: the capacity readout shows the loss.

### Barracks

- **Barracks**: 2×2, the building that trains soldiers. It follows every building rule: it must be built on the power grid and powers a small area of its own, enemies attack it when it is in their way, it joins a barrier, repair yards repair it, and a destroyed barracks leaves nothing behind. **v4 numbers:** 100 HP, a power area of 3 and 200 gold, about seven soldiers or one and two-thirds towers, so the first barracks is a real choice against another tower. A full barracks with its 10 soldiers costs 500.
- **Barracks limit:** at most N barracks, with N a tuning setting starting at 5. The build menu shows the count (for example, "5/5") and greys the barracks out at the limit; a destroyed barracks frees its place. Whether gold alone holds the army down, so the limit can go, is a playtest question.
- **Capacity:** each barracks adds 10 to the player's capacity, so 5 barracks field 50 soldiers, the army the 2 ms unit budget is checked against. A typical game is expected to build 3 or 4. Each soldier takes up one, queued soldiers included. Soldiers don't belong to the barracks that trained them: a destroyed barracks only lowers capacity, and no soldier dies with it. An unpowered barracks still counts. A player over capacity keeps every soldier but can't train until under it again. The HUD shows **Capacity 12/50** beside gold from the first barracks on.
- **Training:** a soldier costs gold only, well under a tower: **30 gold** in v4. Each barracks trains one at a time from a queue of up to 5; shift-click on Train queues 5 at once. Gold is paid on queuing and refunded on cancel. In the build phase training is instant; during a wave each soldier takes 5 seconds, so a soldier needed against a leak arrives late, and planning ahead pays.
- **Interruptions:** while unpowered or under repair, the barracks' timer pauses and resumes where it left off. A destroyed barracks refunds every soldier in its queue; only the building's own gold is lost.
- **New soldiers:** a trained soldier appears on the free cell beside the barracks facing most towards the base, or the nearest free cell outward if those are blocked.
- **Rally point:** with a barracks selected, a right-click on the ground sets its rally point, during a wave, in the build phase or while paused. Each new soldier gets a Move order to it and can be stopped or re-ordered like any Move. Without one, a new soldier stands beside the barracks. It is ground only, shown as a flag and line while the barracks is selected, and cleared from its details.
- **Details:** the barracks' status (Unpowered, else Under repair, else Training or Idle), its queue (click a slot to cancel and refund), **Train soldier** (greyed out when capacity or the queue is full or gold is short, with the reason on hover) and **Clear rally point**.

### The unit in the HUD

- **Command card:** while soldiers are selected, the command card swaps from the build menu to the soldier's commands, and swaps back when the selection clears. **Stop** (S), **targeting** (A) and **Formation** (F) fill the top row; **Next wave** keeps its slot. Targeting and Formation are each one button that flips between their two states and shows the current one. When the selected soldiers' modes differ, targeting shows **Mixed** with neither state pressed, and a click or A sets every one of them, from Mixed to Bloaters first. The build hotkeys still work with soldiers selected, and using one clears the selection, since buildings and soldiers are never selected together.
- **One soldier's details:** HP and max HP, a status (**Moving** while under a Move order, else Firing or Idle), damage, shots/s, range with its high-ground bonus shown apart (for example, "Range 6 (+2 high ground)") and its kills this run.
- **Several soldiers' details:** a title with the count ("8 soldiers"), their kills this run added up, and a grid of small tiles, one per soldier in selection order and coloured by its HP. Clicking a tile selects that soldier alone; shift-click takes it out of the selection.
- **Combo:** one soldier's details show the same ring as a selected building's, in the same spot; several show none.
- **Range:** the selected soldiers' ranges, each at its own elevation, are drawn as one merged shape, a faint fill with a single outline, in the colour of a tower's range circle. It follows the soldiers as they move and climb. One selected soldier is the one-circle case.
- Buildings keep their controls in their details in v4, so a tower's targeting toggle stays there while a soldier's is on the card.

## Towers and economy

- One tower type: single-target, aimed at the enemy closest to the base. From v3, a tower prefers a bloater in its range by default, so long reach ahead of the walls pops bloaters in the open; each tower has a toggle in its details to aim at the closest enemy to the base instead. 5 damage, 3.5 shots/s, range 8 cells, 60 HP, costs 120 gold.
- Towers can only be built on clear cells of the power grid. Building is allowed during waves.
- A tower may cut off every path to the base: enemies then break through the cheapest structure.
- Starting gold: 300, 2.5 towers' worth. The v3 tuning playtest raised it and every building's cost by half (from 200 gold, and 80 for a tower), so the opening is unchanged and the mid and late waves are tighter.
- **Bounty:** each kill pays 1 gold before any combo.
- **Combo:** each building has its own combo; there is none for the whole defence. The building that lands the killing blow gets the kill, and any building that damages enemies can build a combo. Each kill adds 1 to the building's count and restarts its timer; if the timer runs out with no kill, the combo breaks back to ×1. The count sets the building's tier, capped. Each kill pays its bounty times the killing building's tier, at once, the kill that crosses a threshold already paying the new tier, so gold earned mid-burst can be spent during the wave. Kills with no building behind them pay ×1. From v4 a soldier earns by the same rules as a building (see Units). A destroyed building loses its combo and its rebuild starts at ×1; damage to a building or the base does not break one. A high combo needs a dense crowd in front of one building, so it rewards letting pressure build, at the risk of an overflow. **v3 numbers:** a 2 s timer, ×2 from 10 kills, ×3 from 25, capped at ×3. A busy tower kills often enough to hold its timer while a crowd feeds it, and the cap stays at ×3 so the combo doesn't bring back v2's gold surplus.
- **HUD:** **Enemies left** counts the current wave's enemies not yet killed, unspawned ones included, so it starts at the wave size and reaches 0 as the wave ends; in the build phase it shows the next wave's size, followed by its bloater count when it has any (for example, "120 enemies · 3 bloaters"). **Kills** counts the run's kills and is also shown on the game-over screen. A building's combo shows above it as a **ring**, hidden at ×1: its tier in the middle, an outer arc filling towards the next tier, and an inner arc for its timer running down. A kill pulses the ring, a tier-up sends a ring outwards, and a break scatters it. The ring stays the same size on screen at any zoom, in shades of gold so it isn't mistaken for the pressure gauge. The selected building's details show the same ring, larger, with its tier and count, the next tier's threshold, the time left on its timer and its best combo this run. The final art may restyle the ring but keeps what it shows. There is no combo readout for the whole defence. The gold readout flashes on a multiplied payout.

## Waves

- Endless. The next wave starts when the player presses "next wave".
- Wave 1 has 20 enemies. Each wave has 25% more enemies and 5% more enemy HP than the last, so wave 10 is roughly 150 enemies, wave 15 roughly 455 and wave 20 roughly 1,390. (v2 grew 30% a wave; v3 lowers it to cut the gold surplus and keep wave 20 nearer the on-screen target.)
- Enemies spawn in bursts of 16, each on a random cell along the spawn edge, at an average of 10 per second. v3 keeps these on the flared map, where the wider mouths already spread the bursts out.
- **Bloaters** (from v3) appear from wave 5. They take the place of normal enemies, so the wave size is unchanged. Their count steps up slowly whatever the wave's size: 1, then one more every few waves, and each wave rolls once for one fewer or one more, so an early wave sometimes has none. The roll is fixed per run and wave, so the build phase's count always matches the wave. Each bloater takes a random place among the wave's bursts, mixed in with normal enemies; there are no bursts of only bloaters. **v3 numbers:** one more every 6 waves, so a base of 1 for waves 5–10, 2 for 11–16, 3 for 17–22 and 4 from 23; a 25% chance of one fewer and a 10% chance of one more. (Replaced a share of the wave, 2% rising to 5%, after the v3 tuning playtest: with 25% wave growth it gave 23 bloaters at wave 15 and 69 at wave 20.)

## Prototype results

Each prototype is played to answer a question, and what the playtest finds shapes the next one. The full technical record of each is in `docs/specs/`.

### v1: corpse loop

- **Question:** does the corpse loop make the game? After about 10 runs: does the player deliberately place towers to shape where piles form (the most important test), do walls change plans in an enjoyable way, do piles shrinking between waves create real choices, and do 1,000 enemies flowing around piles look and feel good?
- **Found:** the map was too open, so walls rarely formed, and the game was too slow.
- **Led to:** v2 reworks the loop: a narrow map, a fast pace with many enemies on screen so piles and then walls form readily, every structure attackable, and bodies landing where enemies die.

### v2: power, and the corpse loop reworked

- **Question:** does the reworked loop form piles and walls readily, and does power (the power grid, pylons and the repair yard) give building its limits?
- **Found:** the late game could not be broken. From about wave 15, enough towers and repair yards held any wave, however many enemies came, and repair was too strong. The combo reached ×3 only in bursts, and a level's goal felt about right at wave 15.
- **Led to:** v3 is about pressure, so a big enough crowd can break a defence.

### v3: pressure

- **Question:** does pressure make the late game breakable, and give the player real answers to it? A crowd that stalls against a defence builds up until it tumbles over it, the bloater blows holes in piles, walls and buildings, and the grinder, per-building combos and repair as a trade-off are the player's tools.
- **Found:** in tuning, the bloater count first grew far too fast with the waves, so it became a slow stepped count with a per-wave roll. Gold was tightened by raising starting gold and every cost by half, and pile decay was turned off because blasts now clear piles. v3 misses the 1,000-enemy target at 60 fps and was accepted as a prototype as it is.
- **Verdict:** yes. Pressure makes the game more of a challenge.

## Finished game direction

Not built in the prototypes, but decisions should leave room for it.

- **Levels:** three levels, each with its own look and possibly a twist. A level is won by reaching a set wave, which unlocks the next.
- **Level 1** is a narrow map that funnels the swarm a couple of ways, so piles and walls form readily.
- **Map variety:** maps range from narrow to more open. Piles and walls come from the sheer number of enemies in a wave, not from bodies being drawn together.
- **The prototypes stay endless,** with no wave goal.
- **Seeds and procedurally generated levels** are a possible future addition, out of scope for the prototypes. Maps are already stored as validated data, so a generator could produce them.

## Later ideas

### Setting

- The base is a drilling rig mining precious minerals, and the enemies attack to stop it. The tone is Starship Troopers: the player's side is the intrusive, militaristic, authoritarian species, stealing the planet's minerals and wrecking it. Towers may be renamed turrets to fit.
- **Start drill:** a cleared wave is the drill recharging, and the next wave starts when the drill starts again, so **Next wave** could become **Start drill**.

### Enemies

- Brutes that always break walls, and enemies that chase.
- **Seekers:** enemies that seek out buildings even when they are not in the way. One that gets inside the defence goes for other buildings before the base, which gives it a chance to reach a generator and blow it up. Seekers go for units too.
- **Climbing buildings:** a line of towers can exploit overflow. Enemies could get on top of buildings, perhaps only by an overflow tumble, with a limit per building set by its space. On top they attack the building, and perhaps walk along linked buildings to spread the attack. With a hit-chance system, enemies on top could be harder to hit.
- **Jumper:** an enemy that jumps over walls, and over or onto buildings.
- **Small enemies:** die in about one shot, are faster and come in greater numbers: perhaps 2 count as 1 normal enemy in a wave's size. They pass through walls. They first appear on their own at the spawn edges.
- **Carrier:** a bloated flying enemy full of small enemies. It drifts slowly towards the base and, close to it, releases them all. Shot down before then, it dies and releases them where it fell. Only towers can hurt it. Open: whether small enemies collide with each other or share space; either way they must look good in the final art.
- **Boss:** a massive enemy in a level's last wave that walks slowly and destroys everything in its path. Its art changes as it takes damage, as its portrait would (see Dynamic portraits).
- **Bunched late waves:** later waves spawn bigger and more tightly packed, rather than spread out, so they look more menacing.

### Buildings

- A splash/area tower.
- **Build time:** buildings take time to build instead of appearing at once, perhaps dropped in from the sky like StarCraft's Terran buildings.
- **Base turret:** an upgrade that arms the base with a turret of its own.
- **Building upgrades:** towers with a higher fire rate, more damage or longer range; more drones per repair yard (perhaps with power-ups).
- **One-sided walls:** walls that can only be attacked from one side, to encourage overflow to build up. Perhaps bloaters damage them too, and units (if added) walk through them both ways. Unsure: they may undercut the hook of piles building up. Perhaps the player can raise and lower them, like StarCraft's supply depots.
- **Power as a currency:** each building costs power, the base supplies some, and generators add more. A destroyed generator blows up like a bloater. This could absorb the earlier idea of a generator that powers an area cut off from the base's power grid.
- **Clean-up robot:** a ground drone that spends energy removing piles so the player can reorganise, and perhaps also demolishes buildings (selling or demolishing is still missing). It returns to its building to recharge. It works in the build phase, but can't recharge then.
- A ranked queue of assignments for a repair yard.

### Units

- Prompted by a playtest: a few enemies got behind the base and attacked it, and the only answer was a turret the player didn't want there. Units would be selected and directed like StarCraft's, in feel and action.
- **Hero:** the run starts with a hero, such as a giant mech, and different heroes bring different abilities or modifiers.
- **First unit:** the soldier, under Units (v4): machine fire like a turret, selected and ordered one by one or as a box, trained in the barracks. Wary of adding them, as they change the game.
- **Healing near a barracks:** an idle soldier within a few cells of a barracks slowly regains HP during a wave, so pulling a worn soldier back is a choice. v4 only recovers soldiers at a wave's end.
- **Second unit:** a melee unit, space marines in bulky high-tech armour with chainsaw swords, sent to hold back the swarm as it floods through.
- **Line of sight from elevation:** walls blocking a soldier's fire at lower elevation, so standing on a pile lets it see over a wall. Left out of v4, since a soldier holding fire has to show why, and soldiers behind their own wall line would go quiet.
- **Units on buildings:** soldiers, or a later kind of unit, standing on buildings. In v4 buildings are solid to soldiers.
- **More formations:** shapes beyond v4's cluster and line, such as a wedge or a ring, if play asks for them.
- **Drawn lines:** a right-drag draws a line formation, its width and facing set by the drag, as in Total War or Company of Heroes, so the shape is part of the order. v4 reads one Formation setting at order time.
- Units could replace reanimation (raising piles into minions that fight enemies, perhaps with larger piles producing a single brute minion), which is dropped for now, though it ties in with piling up bodies.

### Details and art

- Clicking anything, any unit, enemy or building, shows its details: status, kills, time alive. Open: whether this is performant with enemies as plain data.
- **Connection lost:** when the subject of an open portrait dies, the portrait shows its death (an explosion, a blood splatter), then static and a "connection lost" message.
- **Game log:** a running log of text alerts, such as a soldier dying off screen. v4 shows a soldier's death only where it falls.
- **Building controls on the command card:** a tower's targeting toggle, a barracks' Train and a repair yard's Assign moving from the details to the command card, as the soldier's commands are in v4. To revisit after the v4 playtest. With it, hotkeys get a tidy-up: B opens the build menu, and the card is contextual to what is selected, as the soldier's commands are.
- **Graphs:** graphs of the run, such as gold gained and lost and kills, including live graphs during a wave.
- **Soldiers drawn as a group:** a soldier drawn as several figures that thin out as it loses HP, so 50 soldiers look like an army (Total War, Bad North). It is more than art: losing a figure looks like a death, though only a dead soldier drops a body, it hints at a squad that can't be split, and it multiplies sprites on screen. v4 draws one figure per soldier.
- **Dynamic portraits:** every unit and building has a portrait in its details that reacts, like Doom's face: angry while firing, resting when idle. A building's portrait changes with what it is doing and its HP.
- **Blood:** a burst of blood when an enemy dies, and cells grow bloodier, through several levels, as more enemies die on them.
- **A horde like liquid:** the swarm should read as a flow rather than one mass: pouring over in an overflow, spilling into pockets, smooth to watch. Some of this may already be there and only need the final art, with animations for enemies pressing together, tumbling and fighting.
- A landing animation for bodies, with the final art.
- Combo juice with the final art and audio: sound, effects and floating numbers.

### Levels

- Map themes, each with its own gameplay:
  - Desert, with rocky mountains and lakes or rivers.
  - Jungle, with dense trees, perhaps cut down or dropped by the player.
  - A crashed ship of the player's side, with tight corridors and malfunctioning or burning electronics.
  - An alien hive, slimy, where slime cells slow walking right down.
  - Open to more.
- **Destructible rock:** blasts break rock, opening new routes for the enemies.

### Runs

- Power-ups, including interactions with piles (for example, flame setting piles alight).
- Meta-progression between runs.
- **Overworld map:** a map for choosing levels, perhaps with purchases between them and, later, saving. Open: how detailed it is, whether it holds a management layer, and whether what it holds lasts between runs or only within one.
- Special waves: a wave that, on a small chance, breaks the usual pattern, for example one with an abnormal number of bloaters. Further on, waves that mutate into a random mix of enemy types.
- Wildcards: rule changes for the rest of a run, such as towers firing twice as fast, buildings with more HP or lower enemy counts, and rarer, wilder ones, such as every enemy having a small chance to blow up like a bloater. Perhaps trade-offs: more enemies for a strong power-up. In the story, the drill could strike something extraordinary that grants one at random. How the player gets one is left to a later prototype. They sit close to power-ups, so they may end up as one system.
