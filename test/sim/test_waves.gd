class_name TestWaves
extends RefCounted

## Waves for tests, sent as v5 started them by number.


## No trickle, so a test sees only its waves' enemies.
static func without_trickle(settings: Settings) -> void:
	settings.change("trickle", "interval", 0.0)


## Starts a wave at [param threat] this tick, sized as v5 sized wave [param threat]: at Off (the
## dry size, ×1) with the roll off. Ticks once.
static func send_at(sim: Simulation, threat: float) -> void:
	sim.settings.change("waves", "size_roll", 0)
	sim.queue_command(Commands.JumpToThreat.new(threat))
	sim.queue_command(Commands.SendWave.new())
	sim.tick()


## Kills everything on the field each tick until no wave is open, handing each tick's deaths to
## [param on_deaths]. False when the wave outlasts [param ticks].
static func kill_the_wave(sim: Simulation, on_deaths := Callable(), ticks := 6000) -> bool:
	for tick in ticks:
		if sim.waves.phase == Waves.Phase.QUIET:
			return true
		sim.queue_command(Commands.KillEnemies.new(maxi(1, sim.enemies.count)))
		sim.tick()
		if on_deaths.is_valid():
			on_deaths.call(sim.deaths)
	return sim.waves.phase == Waves.Phase.QUIET
