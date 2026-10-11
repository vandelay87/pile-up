# How crowd sims measure density and pressure

Research for [#93](https://github.com/vandelay87/pile-up/issues/93), informing the grilling [Dense hordes overflow piles and walls (#91)](https://github.com/vandelay87/pile-up/issues/91). It covers how crowd research and games measure density and pressure, how a crush can be found as a group without flicker, how shipped horde games handle crowds piling over obstacles, and fluid-like spill models. It ends with options for pile-up. They are options, not decisions.

Researched October 2026 against `main` at `c532dec`.

## Short answer

- **Density** is almost always "agents per cell", either counted directly or splatted with a smooth kernel (bilinear or Gaussian) so it doesn't jump when an agent crosses a cell edge. pile-up already has the raw count for free: the spatial hash's bucket sizes.
- **Pressure** has three common meanings, and only two fit a *stalled* crowd:
  1. *Turbulence pressure* (Helbing 2007): density × velocity variance. It flags a crowd that shoves in all directions. A crowd pressed motionless against a wall has low variance, so this measure reads it as calm. It's the wrong signal for a crush in pile-up's sense.
  2. *Contact pressure* (Helbing 2000): the summed magnitude of the push forces on an agent. pile-up already computes these pushes in separation.
  3. *Constraint pressure* (Narain 2009): zero until density reaches a maximum packing density, then whatever is needed to stop it going higher. It is nonzero only where the crowd is fully packed, and its gradient points from packed to free space. That gradient is the spill direction.
- **Stability** comes from three standard tools, used together: smooth in space (kernel or cluster average), integrate over time (a leaky accumulator rather than an instant reading), and use hysteresis (start above one threshold, stop below a lower one). Anchoring a crush to the obstacle cells it presses on gives it a stable identity.
- **Shipped games** don't publish their pile-up logic. World War Z's developers say their zombie pyramids are a functional threat that grows until it reaches the player's high ground unless the player topples it. Days Gone's developers describe hordes that "flow like water". No technical postmortem of either mechanic was found.
- **Spill models:** the classic threshold-and-topple rule is the sandpile automaton (Bak, Tang and Wiesenfeld 1987). Its final state doesn't depend on update order (Dhar 1990), which suits pile-up's deterministic sim. "Downhill to the nearest free cell" maps directly onto the integration fields pile-up already has.

## 1. Measuring density

### Count per cell

The cheapest density is the number of agents whose position falls in each cell. pile-up's counting-sort spatial hash already holds it: `_bucket_starts[c + 1] - _bucket_starts[c]` is the count in cell `c` after `rebuild_spatial_hash()` (`src/sim/enemies/enemies.gd`). Reading it costs nothing extra.

The drawback is that the count jumps by a whole agent when one crosses a cell edge, so a threshold on the raw count flickers when the crowd jostles near the boundary. Both of the next two methods exist to remove that jump.

### Bilinear splat (particle-in-cell)

Narain et al. accumulate density on the grid by adding each agent's mass to the four nearest cell centres, weighted by bilinear interpolation, "closely follow[ing] the particle-in-cell method of fluid simulation" ([Narain et al. 2009, §3.2](https://ics-websites.science.uu.nl/docs/vakken/mcrws/papers_new/Narain%20et%20al%20-%202009%20-%20Aggregate%20dynamics%20for%20dense%20crowd%20simulation.pdf)). It also yields an average velocity per cell with the same weights.

Treuille et al. splat the same way, but raise each of the four weights to a power λ so that each person contributes at least ρ̄ = 1/2^λ to their own cell and at most that to neighbours. Their stated requirement is that "the density field must be continuous with respect to the location of the people. Otherwise movement would cause sharp discontinuities in the density, and subsequently in the speed" ([Treuille, Cooper and Popović 2006, §4.1](https://grail.cs.washington.edu/projects/crowd-flows/78-treuille.pdf)).

Cost: four writes per agent into a float array the size of the map, plus clearing it each tick. For 1,000 agents that's about 4,000 adds, cheaper than the separation pass already in the loop.

### Gaussian kernel

Helbing, Johansson and Al-Abideen measure local density at a point as a sum over nearby people of a Gaussian weight, `f(d) = 1/(πR²) · exp(−d²/R²)`, where R is a measurement parameter. About 63% of the weight falls within radius R, and larger R gives smoother, less noisy readings, converging to the plain average N/A as R grows ([Helbing et al. 2007, eqs. 1–2](https://arxiv.org/abs/physics/0701203)). Their density maps were also "determined by Gaussian smoothing in space and time".

On a grid, the equivalent is a small blur (for example a 3×3 kernel) over the per-cell counts, run only on the cells that matter.

### What "dense" means in pile-up's units

Narain et al. derive the maximum packing density from the minimum spacing: `ρmax = 2α / (√3 · d²min)`, the hexagonal packing limit, with α ≤ 1 a slack factor ([Narain et al. 2009, eq. 4](https://ics-websites.science.uu.nl/docs/vakken/mcrws/papers_new/Narain%20et%20al%20-%202009%20-%20Aggregate%20dynamics%20for%20dense%20crowd%20simulation.pdf)).

In `data/settings/defaults.json`, `separation_radius` is 0.3 cells, so the collision spacing is 0.6 cells and the packing limit is about **3.2 enemies per cell**. Personal space (0.7 cells) gives a "comfortable" packing of about **2.4 per cell**. So in pile-up terms, "really dense" sits between roughly 2.4 and 3.2 enemies per cell. These are geometry limits, not tuned values.

For real crowds, G. Keith Still puts the critical density, where flow peaks before falling, at about 2–3 people per m², and notes that it differs between crowds ([Still, Density and flow](https://gkstill.com/Support/crowd-flow/DensityFlow.html)). Helbing et al. found a second flow peak at 9 persons/m² at the Jamarat Bridge, which they link to shockwaves.

## 2. Measuring pressure

### Turbulence pressure: density × velocity variance

Helbing et al. propose `P(r, t) = ρ(r, t) · Var(V)`, "the local pedestrian density times the local velocity variance". At the 2006 Hajj disaster, "turbulent" motion began when P passed 0.02/s², and the accident started about ten minutes later, at P's peak ([Helbing et al. 2007, eq. 9, Fig. 3c](https://arxiv.org/abs/physics/0701203)). They stress that this "gas-kinetic" pressure is distinct from the mechanical pressure people feel, though the two are probably related.

**Fit for pile-up: poor for detection, maybe useful for flavour.** A crowd pinned motionless against a wall has near-zero velocity variance, so P stays low exactly when pile-up wants the gauge to fill. Its critical value also depends on R. It would suit a later "the crush is churning" effect better than the trigger.

### Contact pressure: summed push forces

In the social force model, Helbing, Farkas and Vicsek count a pedestrian as injured, becoming "non-moving obstacles for others", when "the sum of the magnitudes of the radial forces acting on them divided by their circumference exceeds a pressure of 1600 N/m" ([Helbing, Farkas and Vicsek 2000, Fig. 1](https://arxiv.org/abs/cond-mat/0009448)). The paper also notes the real-world mechanics: jammed crowds build "dangerous pressures up to 4,450 Newtons per meter", and fallen people turning into obstacles slows escape further, which is pile-up's pile mechanic in miniature.

**Fit for pile-up: good, and nearly free.** `_separation()` already computes each enemy's per-neighbour shove `direction · (spacing − distance) · push` and, since #89, averages it. Summing the *magnitudes* of those shoves (not the vector, which cancels in a packed crowd) gives a per-enemy contact pressure in the same pass. One caveat: the averaging added in #89 deliberately damps the vector total so packed crowds settle; the magnitude sum would need its own accumulator, and `neighbour_cap` (0, uncapped, by default) bounds how high it can go.

### Constraint pressure: only at maximum density

Narain et al. treat the crowd as "unilaterally incompressible": density may fall freely but may not rise above ρmax. The pressure p is zero wherever ρ < ρmax and positive only where the crowd is fully packed, so "pressure only acts in regions when the density ρ is at the maximum" ([Narain et al. 2009, §4.1, eqs. 7–9](https://ics-websites.science.uu.nl/docs/vakken/mcrws/papers_new/Narain%20et%20al%20-%202009%20-%20Aggregate%20dynamics%20for%20dense%20crowd%20simulation.pdf)). Agents' velocities are corrected by −∇p, so the crowd is pushed from packed cells toward unpacked ones. They blend each agent between its own preferred velocity and the grid velocity by ρ/ρmax.

**Fit for pile-up:** the full solve is a linear complementarity problem, too heavy for GDScript at 60 fps. The *shape* of the idea is cheap, though: "pressure is zero below a packing threshold, then rises", and "spill flows down the pressure gradient". That matches the brief that early waves rarely trigger it.

### Stall-based pressure: density held over time

None of the sources above define pressure as "density held over time", but two of them supply the parts:

- Treuille et al. interpolate speed between free-walking speed below ρmin and the crowd's flow speed above ρmax ([Treuille et al. 2006, §3.2, eq. 10](https://grail.cs.washington.edu/projects/crowd-flows/78-treuille.pdf)), so the *speed deficit* (how much slower an agent moves than it wants to) is a direct readout of congestion.
- Helbing et al. found that the warning signs preceded the disaster by 10 to 30 minutes: stop-and-go flow first, then turbulence, then the accident ([Helbing et al. 2007](https://arxiv.org/abs/physics/0701203)). Duration matters, not only the instant.

pile-up already tracks a per-enemy stall: `_stuck_ticks` counts ticks without progress on the route field near a structure, and `jam_seconds` (0.5 s) turns that into a structure attack. A crush gauge could accumulate the same "wants to move, can't" signal at the group level.

## 3. Finding a crush as a group, without flicker

### Three granularities

| Unit | How | Pros | Cons |
|---|---|---|---|
| **Per enemy** | Each enemy holds its own pressure (contact or stall). | Cheapest; already per-enemy data. | No single place to draw a gauge; noisy; the gauge would have to be aggregated anyway. |
| **Per obstacle cell** | Sum density or pressure over the open cells touching each pile, wall or building face. | Stable identity (the obstacle doesn't move); the gauge has an obvious anchor; matches "the crowd against a pile or wall". | A long wall gives many cells; neighbouring cells of one crush need merging to show one gauge. |
| **Per connected cluster** | Flood-fill or union-find over cells above a density threshold. | Finds the crowd as the player sees it; one gauge per blob. | Cluster identity changes when blobs merge or split, so the gauge can jump; needs matching across ticks. |

Grid clustering is a solved problem: the Hoshen–Kopelman algorithm labels connected clusters on a lattice in one raster pass with union-find, originally for percolation clusters ([Hoshen and Kopelman 1976, Phys. Rev. B 14, 3438](https://doi.org/10.1103/PhysRevB.14.3438)). On a map of a few thousand cells, a pass over only the cells above threshold is cheap.

A hybrid is common in practice: cluster dense cells, but **key each cluster by the obstacle cells it touches** (for example, the lowest-index obstacle cell in contact). That keeps the gauge's identity stable while the crowd shifts, and a crush with no obstacle contact (an open-field jam) can simply not count.

### Stability tools

These are standard control techniques rather than crowd-research results:

- **Spatial smoothing:** a kernel or splat (§1), or averaging over the cluster, so one enemy crossing a cell edge doesn't change the reading.
- **Temporal integration:** a leaky accumulator, `gauge += (reading − leak) · dt`, clamped at 0. It rises only while the crowd *stays* dense, and drains slowly when it thins. This is how "density held over time" becomes one number. Helbing et al.'s "smoothing in space and time" is the measurement-side version.
- **Hysteresis:** a crush starts when the reading passes an upper threshold and ends only when it falls below a lower one, so a reading hovering at the line doesn't toggle.
- **Minimum dwell:** once a crush exists, keep it for at least N ticks.

The leaky accumulator also suits the brief directly: a short burst of density (a clump arriving) leaks away before the gauge fills, so early waves rarely trigger it, while a late-wave crowd pinned against a wall fills it steadily.

## 4. How shipped horde games handle crowds over walls

- **World War Z (Saber Interactive, 2019).** Creative director Oliver Hollis-Leick wrote that the zombie pyramids, "climbing over each other to create a growing pile-up of undead flesh", are "not there because it looks cool": "if you don't topple them, they'll pile high enough to reach any high ground you've managed to secure". Distant swarms run simplified AI and individuals become independent as they close in. Early testers ignored swarms, "thinking they were decorative background scenery until it was too late" ([PlayStation Blog, Dec 2019](https://blog.playstation.com/archive/2019/12/16/horde-mode-z-update-launches-for-zombie-shooter-world-war-z-tomorrow/)). Lessons for pile-up: the pile-up is a visible, growing, *counterable* threat (topple it), and a horde has to read as a threat rather than scenery. Saber's GDC 2019 talk on the game covered rendering, not crowd logic ([GDC Vault](https://gdcvault.com/play/1025817/Advanced-Graphics-Techniques-Tutorial-High)).
- **Days Gone (Bend Studio, 2019).** Hordes "flow like water and kill quickly". Game director John Garvin tells players to treat a horde as a flood: run from the wave and whittle it into smaller waves ([PlayStation Blog, Apr 2019](https://blog.playstation.com/2019/04/25/fighting-the-overwhelming-hordes-of-days-gone/)). Bend's GDC talks covered squad AI, not the horde's movement ([GDC 2018 AI Summit](https://gdconf.com/news/study-ai-freak-o-system-sonys-days-gone-gdc-2018)).
- **They Are Billions (Numantian Games, 2019).** A custom engine for "up to 20,000 units in real time", each with its own AI ([Steam store page](https://store.steampowered.com/app/644930)). Infected break through walls rather than climb them; one infected reaching a building infects everyone in it. No developer write-up of the wall logic was found.
- **Supreme Commander 2 (Gas Powered Games, 2010).** Not a horde game, but the flow-field source: cost fields (255 = wall), integration fields and flow fields per 10×10 sector, with agents that "push each other around as well as slide along walls using physics" ([Emerson, Game AI Pro ch. 23](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter23_Crowd_Pathfinding_and_Steering_Using_Flow_Field_Tiles.pdf)).

**What makes it readable, across these:** the build-up is visible before the breach (World War Z's growing pyramid); there is a player counter while it builds (topple it, or thin the wave); and the crowd reads as one mass with a direction (Days Gone's flood). pile-up's planned gauge above the crush covers the first point explicitly.

**Gap:** none of these studios has published how its pile-up or climb is triggered or simulated. Plague Inc. was named in the ticket; no source on crowds climbing obstacles in it was found.

## 5. Fluid-like spill models

### Threshold and topple (sandpile)

The Bak–Tang–Wiesenfeld sandpile is the textbook threshold-spill automaton: when a cell's value reaches a threshold, it topples, sending one unit to each neighbour, which may push them over in turn, giving avalanches ([Bak, Tang and Wiesenfeld 1987, Phys. Rev. Lett. 59, 381](https://doi.org/10.1103/PhysRevLett.59.381)). Dhar showed that the final state doesn't depend on the order in which cells topple, the "abelian" property ([Dhar 1990, Phys. Rev. Lett. 64, 1613](https://doi.org/10.1103/PhysRevLett.64.1613)). For pile-up, whose sim must be deterministic and whose incremental updates must equal a full rebuild, an order-independent spill rule is a strong property to have.

Mapped to overflow: when a crush's gauge (or a face cell's density) passes the threshold, some enemies "topple" over the obstacle, which lowers the pressure behind them. The rate is set by how many topple per tick. A trickle versus a surge is just how far past the threshold the crowd is.

### Density-controlled speed (Treuille)

Below ρmin, agents move at full speed; above ρmax, they move at the crowd's flow speed; in between, linearly interpolated ([Treuille et al. 2006, eq. 10](https://grail.cs.washington.edu/projects/crowd-flows/78-treuille.pdf)). Transposed to overflow: an enemy's speed *over* an obstacle could scale with the pressure behind it, so a mild crush creeps over and a heavy one pours.

### Flow down the pressure gradient (Narain)

Velocity corrected by −∇p pushes agents from fully packed cells toward less packed ones ([Narain et al. 2009, eq. 6](https://ics-websites.science.uu.nl/docs/vakken/mcrws/papers_new/Narain%20et%20al%20-%202009%20-%20Aggregate%20dynamics%20for%20dense%20crowd%20simulation.pdf)). With pressure defined only per crush, the cheap analogue is: an overflowing enemy moves toward lower density.

### Downhill to the nearest free cell on the flow field

pile-up already has the "downhill" direction: the sensible and direct integration fields give each cell's cost-to-base and true shortest-path parent (`docs/specs/v2.md` §7). An overflowing enemy can follow the **direct** field's parent chain (piles cost nothing extra there and walls almost nothing) from its cell, across the obstacle, to the first cell that is walkable and below a density threshold, and land there. That's the "nearest free cell in the direction of the destination" from #91, and it's a walk along an existing array, not a new search. The existing `_first_obstacle_on_chain()` already walks this chain for route rolls, capped at 40 steps.

## 6. What it would cost in pile-up

Per tick, at about 1,000 enemies, roughly in order of cost:

| Measure | Extra work | Notes |
|---|---|---|
| Count per cell | none | Bucket sizes from the spatial hash. |
| Contact pressure per enemy | one `length()` and add per neighbour pair | Inside the existing separation loop; the loop already computes `distance`. |
| Bilinear splat | about 4 adds per enemy, plus clearing the grid | A `PackedFloat32Array` of map size. |
| Blur or cluster over dense cells | proportional to dense cells, not the map | Only cells above a floor need visiting; most of the map is empty. |
| Per-crush leaky gauge | one update per crush | A handful of crushes at most. |
| Downhill landing walk | up to ~40 parent steps, only for enemies that overflow | Bounded by the overflow rate, not the enemy count. |

The ADR 0001 budget (0.9–1.8 ms per frame for 1,000 enemies on the baseline M5) leaves room for any of these. The expensive items in the literature (Narain's LCP pressure solve, Treuille's per-group eikonal solve) are the ones to avoid.

## 7. Options for pile-up

These are options with trade-offs, for the grilling in #91. None is a recommendation.

### What a crush is

- **A. Per obstacle face.** Open cells touching a pile, wall or building, merged per connected run of the obstacle. Stable, easy to anchor the gauge to, matches the playtest complaint (crowds packing against piles and walls). Misses jams in open ground, which may be the point.
- **B. Per dense cluster, keyed by its obstacle contact.** Flood-fill dense cells, keep the identity of the lowest obstacle cell touched. Closer to what the player sees as one crowd; more code to keep identities stable through merges and splits.
- **C. Per enemy.** Each enemy carries its own pressure and overflows alone. Cheapest, emergent, but no natural place for one gauge, and individual readings flicker.

### What fills the gauge

- **D. Density over a threshold, integrated over time (leaky).** Count or splatted density above roughly the comfortable packing (about 2.4/cell), accumulated and slowly drained. Simple, tunable, and quiet in early waves. Needs two numbers (threshold, leak), plus the fill rate.
- **E. Contact pressure, integrated over time.** Sum of separation shove magnitudes. Closest to "the crowd is pushing", nearly free to compute; depends on separation's tuning, so changing `separation_push` would retune overflow.
- **F. Stall: density × speed deficit, integrated.** Fills only when the crowd is both dense and not getting where it wants. Distinguishes a crowd flowing past an obstacle from one jammed against it; needs a per-enemy "actual versus intended speed" reading.
- **Not recommended by the sources for the trigger:** Helbing's ρ·Var(V), since a pinned crowd has low variance.

### How it spills

- **G. Threshold topple (sandpile-like).** At the threshold, release enemies over the obstacle at a rate that grows with the excess. Order-independent if done as "decide counts, then move", which fits the deterministic sim. Tiers fall out of the excess: a trickle just over, a surge well over.
- **H. Speed scaling (Treuille-like).** Enemies cross the obstacle at a speed set by the pressure behind them, slowed by the pile. Continuous, and they stay shootable on the way; the crossing is visible as a stream rather than a teleport.
- **I. Downhill landing on the direct field.** Walk the direct field's parent chain past the obstacle to the first free, not-dense cell. Reuses existing arrays; matches "nearest free cell toward the destination". Pairs with G or H for the motion itself.

### Stability, whichever is chosen

Hysteresis on start and stop, a leaky accumulator rather than an instant reading, and identity anchored to obstacle cells. All three are cheap and independent of the choices above.

## Sources

Primary, read for this note:

- Helbing, D., Johansson, A. and Al-Abideen, H. Z. (2007). "The dynamics of crowd disasters: An empirical study." *Phys. Rev. E* 75, 046109. [arXiv:physics/0701203](https://arxiv.org/abs/physics/0701203)
- Helbing, D., Farkas, I. and Vicsek, T. (2000). "Simulating dynamical features of escape panic." *Nature* 407, 487–490. [arXiv:cond-mat/0009448](https://arxiv.org/abs/cond-mat/0009448)
- Treuille, A., Cooper, S. and Popović, Z. (2006). "Continuum crowds." *ACM Trans. Graph.* 25(3), 1160–1168. [PDF (UW GRAIL)](https://grail.cs.washington.edu/projects/crowd-flows/78-treuille.pdf)
- Narain, R., Golas, A., Curtis, S. and Lin, M. C. (2009). "Aggregate dynamics for dense crowd simulation." *ACM Trans. Graph.* 28(5), 122. [Project page](https://gamma.cs.unc.edu/DenseCrowds), [PDF](https://ics-websites.science.uu.nl/docs/vakken/mcrws/papers_new/Narain%20et%20al%20-%202009%20-%20Aggregate%20dynamics%20for%20dense%20crowd%20simulation.pdf)
- Emerson, E. (2013). "Crowd pathfinding and steering using flow field tiles." *Game AI Pro*, ch. 23. [PDF](http://www.gameaipro.com/GameAIPro/GameAIPro_Chapter23_Crowd_Pathfinding_and_Steering_Using_Flow_Field_Tiles.pdf)
- Hollis-Leick, O. (2019). World War Z developer post. [PlayStation Blog](https://blog.playstation.com/archive/2019/12/16/horde-mode-z-update-launches-for-zombie-shooter-world-war-z-tomorrow/)
- Turi, T., with Garvin, J. and Ross, J. (2019). "Fighting the overwhelming hordes of Days Gone." [PlayStation Blog](https://blog.playstation.com/2019/04/25/fighting-the-overwhelming-hordes-of-days-gone/)
- Numantian Games. They Are Billions. [Steam store page](https://store.steampowered.com/app/644930)
- Still, G. K. Density and flow. [gkstill.com](https://gkstill.com/Support/crowd-flow/DensityFlow.html)

Cited by reference, not re-read for this note (standard results):

- Bak, P., Tang, C. and Wiesenfeld, K. (1987). "Self-organized criticality: An explanation of the 1/f noise." *Phys. Rev. Lett.* 59, 381. [doi:10.1103/PhysRevLett.59.381](https://doi.org/10.1103/PhysRevLett.59.381)
- Dhar, D. (1990). "Self-organized critical state of sandpile automaton models." *Phys. Rev. Lett.* 64, 1613. [doi:10.1103/PhysRevLett.64.1613](https://doi.org/10.1103/PhysRevLett.64.1613)
- Hoshen, J. and Kopelman, R. (1976). "Percolation and cluster distribution. I." *Phys. Rev. B* 14, 3438. [doi:10.1103/PhysRevB.14.3438](https://doi.org/10.1103/PhysRevB.14.3438)

Code read: `src/sim/enemies/enemies.gd` (spatial hash, `_separation`, `_personal_space`, `_structure_target`), `data/settings/defaults.json`, `docs/specs/v2.md` §7–§9, `docs/adr/0001-enemies-as-packed-arrays.md`.
