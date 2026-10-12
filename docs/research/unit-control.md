# How tower defences with units handle control

Research for [#159](https://github.com/vandelay87/pile-up/issues/159), feeding [What the player controls: squad or soldier, and which commands (#160)](https://github.com/vandelay87/pile-up/issues/160) under the v4 map [#156](https://github.com/vandelay87/pile-up/issues/156). It looks at how comparable games hand the player units alongside (or instead of) static defences, and how much control they give. It ends with options for pile-up. They are options, not decisions.

Researched October 2026 against `main` at `d0d9ceb`.

## Short answer

- **Two families.** Tower defences with units (Kingdom Rush, Bad North) hand over a *group* and almost no commands: put it here, and it fights on its own. RTS-defence hybrids (They Are Billions, Diplomacy is Not an Option, Mindustry since v7) hand over *individual units* with the full StarCraft kit: box select, control groups, move, attack, hold, patrol. The no-unit baseline (Defense Grid, Dungeon Warfare) puts all skill into placement.
- **Squad is the norm when units are a sideline.** Kingdom Rush's barracks soldiers, Bad North's squads and Mindustry's unit factories all treat the building or commander as the thing the player points, with the soldiers inside it expendable and refilled on a timer.
- **The command set that survives in "lite" designs is one verb:** a position (Kingdom Rush's rally point, Bad North's grid tile). Units choose their own targets. Bad North's developers say outright that they cut "the number and frequency of actions" so the game suits people who like "the idea of playing strategy games more than the reality".
- **Where control stops being fun**, in reviews and player threads: precise placement of large groups (They Are Billions on controllers; Mindustry's v7 "finicky" groups), units that walk past enemies because they only obey a move order (They Are Billions' Hold; DINO's guards ignoring mobs "just outside their aggro range"), and attention pulled between base and army (DINO). The hybrids lean on **pause-and-order** to make individual control bearable; They Are Billions' director says pause is there "to encourage strategic thinking over the player's control skills".
- **Blocking:** Kingdom Rush's soldiers exist *to* block (each holds one enemy in melee), which is why it pins them to a short rally range. In the swarm games, units are things the horde eats; They Are Billions punishes a unit's noise by drawing more of the swarm.

## The games

### Kingdom Rush (Ironhide, 2011 onward)

- **What the player controls:** the barracks, not the soldiers. "A given Barracks building places its 3 soldiers around a location along the path, and the soldiers wait for enemies to draw near enough the location before charging into battle. This location can be changed by the Rally command. The location can only be set within the Rally Range of a Barracks" ([Harlow, *Kingdom Rush – the wonderful campaign level design*, Game Developer, 2013](https://www.gamedeveloper.com/design/kingdom-rush---the-wonderful-campaign-level-design)). Separately, each level has one **hero**, a single unit the player taps and then taps a destination for; heroes cast their abilities automatically, and Ironhide frames the player's job as "putting the Hero in the right place at the right time" (fan wiki and developer reply summarised via [Kingdom Rush wiki, Heroes](https://kingdomrushtd.fandom.com/wiki/Category:Heroes); secondary, not checked first-hand). A **Call Reinforcements** spell drops two short-lived farmers anywhere on the path ([wiki, Call Reinforcements](https://kingdomrushtd.fandom.com/wiki/Call_Reinforcements); secondary).
- **Command set:** one, rally point, within a leash. No attack orders, no stances.
- **Selection and grouping:** tap a barracks (or its tower menu's flag) then tap the ground. No multi-select, no control groups.
- **Obtained and replaced:** built as a tower on fixed build spots; dead soldiers respawn on a timer. "Your soldiers from the Barracks do respawn, but it takes 10 seconds that the enemies can take advantage of to slip by" (Harlow). Guides add that upgrading the barracks retrains them at once with full health (secondary).
- **Blocking:** the point of the unit. Soldiers "engage enemies in melee combat, which forces them to stop… Each soldier stops only one enemy tops" (Harlow). They can't stop flyers. Harlow names the barracks as what "makes Kingdom Rush unique".
- **Where it stops being fun:** no review found criticising barracks control; the leash and auto-targeting keep it to a few taps per wave. The cost appears instead as positional puzzles (when to rally soldiers away from archers' targets, the 10-second respawn gap).

### Bad North (Plausible Concept, 2018)

- **What the player controls:** squads, each led by a commander. Players are mostly "positioning their squads on a grid" while "each of the units in that squad decide how/when to attack from there", which the developers call a "very low granularity of interaction" ([Nintendo UK interview, April 2018](https://www.nintendo.com/en-gb/News/2018/April/Interview-Taking-on-hordes-of-invading-Vikings-in-Bad-North-1368315.html)). Up to four commanders per battle ([Nintendo World Report review, Aug 2018](https://www.nintendoworldreport.com/review/48095)).
- **Command set:** move to a tile, plus later upgrade abilities such as "telling your archers to bombard a particular spot", which "won't form the core of your strategy" (Nintendo UK). Time slows while an order is being given (Meredith, [Nintendo Life, May 2018](https://www.nintendolife.com/news/2018/05/feature_battling_the_viking_horde_with_bad_north_dev_plausible_concept)).
- **Selection and grouping:** one squad at a time, by button or touch; the squad is the group.
- **Obtained and replaced:** commanders are recruited between islands. "Each one of the soldiers in a unit is expendable… you can lose them and just replenish them. With the hero characters it is ultimately permadeath" (Meredith, Nintendo Life).
- **Blocking:** squads physically hold ground (pikes on a beach, infantry at a choke); the game is built around this.
- **Design intent:** "keep interactions and UI super lightweight", against strategy games that "require you to be constantly micromanaging everything"; "reduce the number and frequency of actions"; "a game for people who like the idea of playing strategy games more than the reality" (Nintendo UK).
- **Where it stops being fun:** reviews fault the roguelite punishment ("once things start to go south in your campaign, you're basically screwed"), not the control (Nintendo World Report).

### They Are Billions (Numantian, 2017–2019)

- **What the player controls:** individual soldiers, RTS style, over a swarm the engine can move by the tens of thousands ("up to 20,000 units simultaneously", [Numantian announcement, 2017](https://numantiangames.com/News/2017-05-31-new-game-they-are-billions/); later 30,000, [GamesBeat, 2018](https://gamesbeat.com/the-making-of-early-access-hit-they-are-billions/)).
- **Command set:** move, attack (attack-move when clicking empty ground), hold (H), patrol, chase (C) ([Keen Gamer guide](https://www.keengamer.com/articles/guides/they-are-billions-survival-guide/); [Steam thread on attack-move](https://steamcommunity.com/app/644930/discussions/0/1617220671493636829); secondary). Hold matters because a moving unit "will walk straight past any danger to get to that point even if it's being attacked" (Keen Gamer).
- **Selection and grouping:** box select, Ctrl+number control groups, F2 selects the whole army (Keen Gamer). Players report running six or more control groups.
- **Pause:** the game pauses at any time and orders can be given while paused: "In Pause Mode, you can place structures to build, give orders to your army" (Numantian). Director Jesús Arribas added pause "to encourage strategic thinking over the player's control skills" (GamesBeat).
- **Obtained and replaced:** trained individually in a Soldiers' Center for resources, with upkeep; no automatic replacement. Units level up from kills.
- **Blocking and swarming:** walls, towers and traps do the holding; units are a mobile reserve and scouts. Noise draws the swarm, so loud units (soldiers, snipers) attract more infected; players favour quiet rangers early ([Steam threads summarised via search](https://steamcommunity.com/app/644930/discussions/0/1620599015888851431); secondary).
- **Where it stops being fun:** precise handling of groups. On consoles, "the fine work necessary to select and maneuver individual units is nigh-impossible with a thumbstick" ([Gamecritics, July 2019](https://gamecritics.com/daniel-weissenberger/they-are-billions-ps4-review/)); [Gamereactor](https://www.gamereactor.eu/they-are-billions-review/) and [Game Informer](https://www.gameinformer.com/index.php/review/they-are-billions/turning-back-the-fetid-tide) say the same. Early PC players called the pathfinding poor, with troops stuck on corners (secondary).

### Diplomacy is Not an Option (Door 407, 2022–2024)

- **What the player controls:** individual units, RTS style, with an "active pause" ([Steam store page](https://store.steampowered.com/app/1272320/Diplomacy_is_Not_an_Option/)): "Play battles in real-time or use pause constantly to keep everything in your hands." Waves of "over 25 THOUSAND" enemies.
- **Command set:** move, a "move to attack" toggle, patrol between two points, guard by parking.
- **Where it stops being fun:** a player thread lists the friction ([Steam, Nov 2024](https://steamcommunity.com/app/1272320/discussions/0/4635988286620359581)): attack-while-moving must be re-selected on every order; guards let "mobs walk right past them just outside of their aggro range"; there is "no option to set units to defend an area"; patrols have only two points. A review notes the strain of juggling: "It's difficult to focus on exploring and clearing the map while remembering to jump back to base" ([GamingTrend, March 2025](https://gamingtrend.com/reviews/diplomacy-is-not-an-option-review-of-physics-and-food/)). Units on walls and towers get range, so the static defence and units combine.

### Mindustry (Anuke, v7 2022 onward)

Checked against source at [`17012d61d9`](https://github.com/Anuken/Mindustry/tree/17012d61d9).

- **What the player controls:** individual units, plus the player's own ship. v7 replaced "the old command center and formation mechanics… with a 'RTS' command system. On desktop, holding [Shift] places you in 'Command Mode'… Left-click to select groups of units, and right-click to order them to locations or targets" ([v136 release notes](https://github.com/Anuken/Mindustry/releases/tag/v136)).
- **Command set:** per-unit-type commands: move, repair, rebuild, assist, mine, and payload loading ([`UnitCommand.java`](https://github.com/Anuken/Mindustry/blob/17012d61d9/core/src/mindustry/ai/UnitCommand.java)), plus stances: stop, hold fire, pursue target, patrol, ram, boost, hold position ([`UnitStance.java`](https://github.com/Anuken/Mindustry/blob/17012d61d9/core/src/mindustry/ai/UnitStance.java)). Orders queue (middle mouse, up to 50; [`CommandAI.java`](https://github.com/Anuken/Mindustry/blob/17012d61d9/core/src/mindustry/ai/types/CommandAI.java), [`Binding.java`](https://github.com/Anuken/Mindustry/blob/17012d61d9/core/src/mindustry/input/Binding.java)).
- **Selection and grouping:** box select in command mode, select all units (G), select all unit factories (H), select across the screen (Alt), and control groups with Ctrl+number ([`DesktopInput.java`](https://github.com/Anuken/Mindustry/blob/17012d61d9/core/src/mindustry/input/DesktopInput.java)).
- **Obtained and replaced:** built continuously by unit factories from items, up to a team unit cap (the wave team has none; [`Units.getCap`](https://github.com/Anuken/Mindustry/blob/17012d61d9/core/src/mindustry/entities/Units.java)). A factory carries a default **command** and a **command position** that its new units take on ([`UnitFactory.java`](https://github.com/Anuken/Mindustry/blob/17012d61d9/core/src/mindustry/world/blocks/units/UnitFactory.java)); in effect a rally point on the building, so a stream of units can be sent somewhere with no per-unit orders.
- **Where it stops being fun:** players missed v6's simpler "follow me in formation" and command-center attack/rally/idle switch. v7 control is "barebones and feels really bad", "very janky to use"; one player "paused often because the control was so finicky" during critical attacks ([Steam, 2023](https://steamcommunity.com/app/1127400/discussions/0/3810656958853608600); [Steam, 2024](https://steamcommunity.com/app/1127400/discussions/0/4631484492942497959)). The v6 design was the lite one: a single global switch for all units.

### No-unit baseline: Defense Grid and Dungeon Warfare

- **Defense Grid: The Awakening** gives the player only towers ("10 different tower types with 3 levels of capability each") to protect power cores; there are no units to direct ([Steam store page](https://store.steampowered.com/app/18500/Defense_Grid_The_Awakening/)). All decisions are placement, upgrades and the path the towers force.
- **Dungeon Warfare 2** is the same with traps: "defend dungeon stages using traps and other hazards against waves of enemies", 33 traps, no units ([Wikipedia](https://en.wikipedia.org/wiki/Dungeon_Warfare_2); [Steam](https://store.steampowered.com/app/698540)).
- What the baseline shows: a leak in these games is answered only by building ahead of time, the gap pile-up's v3 playtest hit.

## Comparison

| Game | Player directs | Commands | Grouping | Replacement | Blocks? |
|---|---|---|---|---|---|
| Kingdom Rush | barracks (3 soldiers) + 1 hero | rally point in a leash; hero move | none | free respawn, 10 s | yes, 1 enemy per soldier |
| Bad North | squad (commander + troops) | move to tile; rare ability | squad is the group | troops refill; commander permadeath | yes |
| They Are Billions | each soldier | move, attack(-move), hold, patrol, chase | box, control groups, select all | train and pay again | no; walls do |
| DINO | each soldier | move, attack-move toggle, patrol | box, control groups | train and pay again | partly, from walls/towers |
| Mindustry v7+ | each unit | move, stances, utility commands, queue | box, groups, select all; factory default | factory output, unit cap | not checked |
| Defense Grid, Dungeon Warfare | nothing | — | — | — | towers/traps only |

## Options for pile-up

These are the shapes the evidence points to, for the human to choose between on #160.

1. **Squad as the unit, one command (Kingdom Rush / Bad North).** The player selects a squad of ~10 and gives it a position; soldiers pick targets themselves, and losses refill at the armoury. Fewest actions per wave; best fit for "lite RTS, never an RTS" and for a fire squad that already fires like a turret. Risk: little of the StarCraft feel the design notes ask for.
2. **Squad as the unit, a small StarCraft set.** The same squad, but with move, attack-move, hold and stop, box select over squads and control groups. Keeps the StarCraft feel at the squad level. The evidence says hold (or move-that-fights) is the command players miss most when it's absent (They Are Billions, DINO).
3. **Each soldier (They Are Billions / Mindustry).** Full RTS selection. The evidence says it drifts toward micromanagement and depends on pause and good pathing to stay fun, both costly beside a 1,000-enemy sim.
- **A building rally point** (Kingdom Rush leash, Mindustry factory command position) fits any of the three: new or refilled soldiers go to it without orders.
- **Pause-and-order** is how the RTS hybrids make control bearable; its designers frame it as favouring strategy over execution. Whether pile-up directs in real time only, in the build phase too, or with a pause is part of #160.
- **Blocking:** only the melee-blocking games make units part of the wall. A ranged fire squad in a swarm game is closer to They Are Billions' troops: something the horde can swarm, kept behind or atop static defences (or, for pile-up, piles).

## Gaps

- Kingdom Rush hero controls and reinforcements come from a fan wiki summarised through search; the wiki blocked direct fetching.
- They Are Billions' full hotkey list wasn't found in a first-party source.
- No review or thread was found criticising Kingdom Rush's barracks control, so "where it stops being fun" for that game is inferred from its design, not sourced.
- Mindustry's unit-to-enemy blocking wasn't checked in source.
