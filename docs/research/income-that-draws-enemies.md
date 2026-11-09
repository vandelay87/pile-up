# Prior art: income that draws enemies

Research for [#266](https://github.com/vandelay87/pile-up/issues/266), feeding the v6 map [#265](https://github.com/vandelay87/pile-up/issues/265): **How the player controls the mining pace** and **How enemies arrive**.

Question: how do other games tie the player's income to the threat they face, and what made it work or feel bad? For each game: what the player controls, how threat scales with it, whether the player can pause it, and what players and reviewers praise or complain about.

Source trust is marked on each claim. **Official** means the developer's own wiki, blog or source code. **Community** means a community wiki, a guide or a forum thread; treat those numbers as likely but unverified. Several official wikis (They Are Billions on Fandom, Against the Storm on the Hooded Horse wiki) refused automated fetches, so their content is quoted through search snippets and marked as such.

## Summary table

| Game | Player controls | Threat scales with | Can the player ease off? | Coupling |
|---|---|---|---|---|
| Factorio | Expansion and production rate (pollution per minute per machine) | Attack frequency from pollution absorbed by nests; evolution (enemy tier) from pollution, time and nests killed | Partly: less pollution means fewer attacks, but time-based evolution never stops | Continuous, strong |
| Dome Keeper | How long to stay mining underground, and how much to mine | Wave weight from resources mined, gadgets brought home, and wave count | No pause: the wave timer always runs; mining less only slows the growth | Fixed timer, income-weighted size |
| Against the Storm | Woodcutters assigned, glades opened | Hostility level (penalties) from woodcutters, trees felled, glades, villager count and time | Yes: unassigning woodcutters lowers hostility | Continuous dial, stepped penalties |
| They Are Billions | Expansion, and which buildings and units make noise | Noise draws nearby infected; scheduled waves on a calendar regardless | Waves: no. Noise: yes, by building and fighting quietly | Waves fixed; noise local and continuous |
| The Riftbreaker | Expansion, HQ upgrades | Timed waves scaled by difficulty and time; HQ upgrade triggers a special attack; harder creatures further from spawn | Waves: no. Escalation: yes, by delaying the HQ upgrade | Mostly decoupled; one opt-in surge |
| Mindustry | Nothing ties income to threat | Waves on a timer (default 2 minutes), optionally paused until the field is clear; the player can call a wave early | Yes, via "next wave" or rules | Decoupled |
| Creeper World | Nothing ties income to threat | Creeper emitters pump on their own schedule | No | Decoupled |
| Darkest Dungeon (non-RTS analogue) | Light level, a free dial | Lower light: more loot, more danger | Yes, at any time, in either direction | Continuous dial, stepped bands |

## Factorio: pollution drives attacks, evolution drives tier

**What the player controls.** Every machine emits pollution per minute at full power (official wiki: stone furnace 2, electric mining drill 10, boiler 30, big mining drill 40). The player controls it indirectly through how much they build and run, cleaner tiers of machine (assembling machine 1 to 3: 4, 3, 2), and by not expanding toward nests. Tiles and trees absorb pollution, so terrain matters ([Pollution](https://wiki.factorio.com/Pollution), official).

**How threat scales.** Two separate channels ([Enemies](https://wiki.factorio.com/Enemies), official):

- **Attack frequency** comes from pollution reaching nests. A nest in a polluted chunk absorbs pollution and spends it to recruit units into an attack group (small biter costs 4, behemoth 400). Groups launch every 1 to 10 minutes. Nests spawn units freely, "but units only attack when pollution reaches a nest."
- **Enemy tier (evolution)** rises from three sources: time (0.000004 per second), pollution produced (0.0000009 per unit, counted at the machine, so absorbing it later does not help), and nests destroyed (0.002 each). The total is squashed so it approaches 1 and gains slow sharply near the top.

**A tuning lesson from the developers.** Wube found during 0.17 that nests could stockpile far more pollution than they could use, so "the amount of attacks might be the same" whether a base polluted a little or a lot, which broke the link between player behaviour and threat. The fix capped each nest's stored pollution at three times its dearest unit ([FFF #283](https://www.factorio.com/blog/post/fff-283), official). A later migration noted pollution had been raising evolution about 16.6 times faster than intended in old saves ([FFF #286](https://www.factorio.com/blog/post/fff-286), official). Lesson: a "more income, more enemies" link silently saturates unless something caps the stockpile, and players notice when easing off does nothing.

**Can the player ease off?** Partly. Producing less pollution means fewer attacks, but time-based evolution never stops, so idling still costs. The map can also be set to peaceful mode, where enemies only fight back when attacked and do not expand ([Peaceful mode](https://wiki.factorio.com/Peaceful_mode), official).

**Praise and complaints.** Players who keep biters on say they add outside pressure that gives the military tech tree a purpose; players who switch from peaceful to biters report finding "a whole section of the tech tree" redundant without them ([r/factorio, 2024](https://www.reddit.com/r/factorio/comments/1cnalgl/biters_off_changed_my_mind), community). The common complaint is the opposite: attacks interrupt the building that most players come for, and a large share of players turn them off or to peaceful, especially on a first run ([forum thread](https://forums.factorio.com/viewtopic.php?p=621117), community). No survey with numbers was found.

## Dome Keeper: mining sets wave size, the timer never stops

**What the player controls.** The keeper digs underground while a wave timer counts down, and must return to the dome to defend. How much to mine, and how long to stay down, is the risk choice (TechRadar's headline: "This mining roguelike punishes greed", [feature](https://www.techradar.com/features/dome-keepers-pacific-rim-style-monsters-test-your-self-restraint)).

**How threat scales.** Wave weight grows with resources mined ("even without bringing them back to the dome"), gadgets brought home, and wave count; one player notes resource-driven difficulty "does not matter after wave 10 or so" as wave count dominates ([Steam thread](https://steamcommunity.com/app/1637320/discussions/0/5704402939715471022), community; no developer confirmation found).

**Can the player ease off?** No. The timer runs regardless; mining less only slows how big the waves get.

**Praise and complaints.** Reviewers praise the tension of the countdown while underground, and the dig-or-return choice it creates. The main pitfall is the one noted above: once the time term dominates, mining harder stops feeling like it draws enemies, so the risk choice fades late in a run.

## Against the Storm: a woodcutting dial against Hostility

**What the player controls.** How many villagers cut wood, and when to open new glades (map areas). Both are needed for income and growth.

**How threat scales.** Hostility rises with woodcutters assigned, trees felled (the official wiki snippet: every 10 felled trees add 2 Hostility points), glades opened, villager count and time. Hostility climbs in levels, and each level adds a penalty to the settlement ([Hostility](https://hoodedhorse.com/wiki/Against_the_Storm/Hostility), [Lowering Hostility](https://wiki.hoodedhorse.com/Against_the_Storm/Lowering_Hostility), official wiki via search snippets; the pages refused direct fetch). The wiki advises taking woodcutters off during the Storm season, when hostility penalties bite hardest. The developers raised the hostility from woodcutters in a patch ([Eremite news](https://eremitegames.com/quality-of-life-update-june-23/), official), and players' per-woodcutter estimates differ by difficulty and patch ([Steam thread](https://steamcommunity.com/app/1336490/discussions/0/3770111248594183670), community).

**Can the player ease off?** Yes, and the game is designed around doing so: unassign woodcutters for the dangerous season, reassign them in the calm one. The time and villager terms still rise, so easing off slows threat rather than stopping it.

**Praise and complaints.** Players treat the woodcutter count as a live dial and time it against the seasons; it is the closest prior art to pile-up's option (a). The friction is visibility: players ask how many points each source adds, and the answer lives in a hover tooltip rather than on screen.

## They Are Billions: fixed waves plus noise

**What the player controls.** Expansion, and noise: which buildings run and which units fight. Community sources say production buildings such as sawmills and quarries make noise constantly, loud units such as soldiers draw infected, and quiet ones such as rangers do not ([Steam thread](https://steamcommunity.com/app/644930/discussions/0/1697174779845532460), community).

**How threat scales.** Two layers. Waves come on a fixed calendar, announced ahead, ending in a final wave from every direction (community wiki via search snippets). Separately, noise is simulated as an "activity" value, and each infected in range rolls to hear it, so loud play pulls in more of the map's existing infected; fights create noise, which can snowball. Villages of infected send raiders on a schedule and can be triggered by noise (Numantian's [Villages of Doom](https://numantiangames.com/News/2017-08-23-they-are-billions-update-the-villages-of-doom/), official; mechanics via community wiki snippets).

**Can the player ease off?** Not from waves; they arrive on the calendar. Noise can be kept down by spacing units and building quietly.

**Praise and complaints.** Players praise the dread of the scheduled final wave and the "one leak ends the run" stakes. Strong players report waiting many in-game days for the next wave with nothing to do ([Steam thread](https://steamcommunity.com/app/644930/discussions/0/4626981776940605049), community): fixed waves that ignore income leave a good economy with dead time.

## The Riftbreaker: timed waves, an opt-in surge

**What the player controls.** Expansion across a large map, and when to upgrade the HQ.

**How threat scales.** EXOR says attack waves are "generated based on the game's base difficulty level and a number of additional factors" without naming them; the wave interval defaults to about 4 to 8 minutes and is a custom difficulty setting, as are wave strength and an attacks-per-wave multiplier ([custom difficulty](https://www.exorstudios.com/blog/custom-difficulty-settings), official). Waves grow stronger over time, creatures get harder the further the player builds from the start, and **upgrading the HQ triggers a special attack wave** ([Survival](https://riftbreaker.gamecore.wiki/en/game_mechanics/survival/), community). No primary source was found saying harvesters or mining rate draw attacks; the mining-draws-attacks idea is better shown by Factorio and Dome Keeper.

**Can the player ease off?** Waves keep coming on their interval. The HQ upgrade is an escalation the player chooses when to trigger, a surge they opt into.

**Praise and complaints.** Players disagree about how threat scales, which suggests it is not well communicated ([Steam thread](https://steamcommunity.com/app/780310/discussions/0/598536186508878847/), community). One complaint: attacks arrive while the player is away building elsewhere ([Steam thread](https://steamcommunity.com/app/780310/discussions/0/4137186326783481146), community).

## Mindustry and Creeper World: decoupled, for contrast

**Mindustry** waves come on a timer (default `waveSpacing = 2 * Time.toMinutes`), the first wave gets double the spacing, `waitEnemies` pauses the timer until all enemies are destroyed, and `waveSending` lets the player call the next wave early ([Rules.java](https://github.com/Anuken/Mindustry/blob/master/core/src/mindustry/game/Rules.java), official source). Income does not affect threat; the player's only lever is calling waves early, which is pile-up v5's Next wave.

**Creeper World** (Knuckle Cracker) uses emitters that pump creeper on their own schedule; the player's energy economy does not change the creeper's output. It shows a fixed, readable threat where all the tension comes from map position and fronts rather than from income choices.

## Off-genre analogue: Darkest Dungeon's light meter

The player can lower light at any time (25 per step) or raise it with torches. Lower light gives more loot (extra battle loot chance 25% Radiant up to 75% Dark) and worse odds: heroes surprised, more stress, more monster damage and crit, and at zero light a chance of a boss ambush ([Light Meter](https://darkestdungeon.wiki.gg/wiki/Light_Meter), official wiki). A continuous dial with stepped bands, a clear readout, and a cost to raise but not to lower: a well-liked model of "choose your own risk for more reward".

## Synthesis for pile-up's three shapes

### Patterns that worked

1. **A visible threat reading next to the control.** Darkest Dungeon's light bands and They Are Billions' wave calendar are readable at a glance; Against the Storm and Riftbreaker players complain when the sources of threat are hidden in tooltips or unclear.
2. **A floor that time alone raises.** Factorio's time evolution, Dome Keeper's wave count, and Against the Storm's time and villager terms all keep threat rising even when the player eases off. This is the "pausing is never free" rule already in #265's notes.
3. **Easing off is real but partial.** The best-liked dials (Against the Storm woodcutters, Darkest Dungeon light) let the player turn threat down meaningfully for a dangerous stretch, without making idling safe.
4. **Opt-in surges.** Riftbreaker's HQ upgrade and Mindustry's call-the-next-wave give the player a chosen moment to take a spike, which suits players who want to prepare.

### Pitfalls

1. **Saturation.** Factorio's pre-0.17 nests stockpiled pollution, so attacks stopped tracking it; Dome Keeper's resource term fades behind wave count. If the faster-mining term stops mattering, the dial is decoration. Cap the buffer and keep the income term large late in a run.
2. **Dead time.** Fixed waves that ignore income (They Are Billions, Mindustry with timer) leave a strong player waiting. Coupling waves to income removes this; a drill-off pause would bring it back unless scattered enemies keep coming.
3. **Interrupting what players came for.** Factorio's main complaint is attacks interrupting building. In pile-up the defence is the point, so this risk is smaller, but a dial left at zero must not become the optimal way to build in peace.
4. **Hidden numbers.** Players misread how threat scales in Riftbreaker and Against the Storm. Show the rate.

### Against the three candidate shapes

- **(a) Continuous mining-speed dial, no waves.** Closest prior art: Factorio's pollution (continuous attacks) and Against the Storm's woodcutters. Works if the dial's effect is visible and stays strong late; needs a time floor so a low dial is not safe, and needs some texture (Factorio's groups mustering every 1 to 10 minutes) so a continuous stream does not feel flat. Losing waves loses the build-phase rhythm and the dread of a scheduled spike.
- **(b) Drill on/off with waves kept.** Closest prior art: Dome Keeper (mine between waves) and They Are Billions (waves plus a quiet/loud layer). Simple to read, keeps v5's rhythm. Risk: on/off is a coarse choice, likely to settle into "always on except when in trouble", and "off" is a pause that brings back dead time unless scattered enemies keep coming. Mining amount should set wave size, as in Dome Keeper, or the choice is flat.
- **(c) Hybrid: dial driving surges.** Closest prior art: Factorio, where continuous pollution is turned into discrete attack groups, and Riftbreaker's opt-in HQ surge. Keeps a dial for the risk choice and spikes for drama and build-phase moments; needs the saturation cap and a visible "surge building up" readout so the player can see the dial working.

Across all three, the prior art says the same three things: show the threat beside the control, let time raise a floor, and make sure mining harder keeps mattering to the end.
