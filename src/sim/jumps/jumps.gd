class_name Jumps
extends RefCounted

## Jumpers' jumps. A ready jumper (walking, its cooldown run out) that would start attacking a
## structure asks [method try_start] instead; if [Flights] plans it a way over at most
## [member Settings.jumper_reach] wall and building cells, it crouches on the spot, then flies that
## way in a fixed air time whatever its length, and lands beyond, perched on a building or the
## base when its plan says so. Its cooldown starts as it lands. A jump records each wall cell it
## crosses for the knock-off, is ground by each working grinder cell it enters, and takes nothing
## off any gauge.

var _settings: Settings
var _enemies: Enemies
var _buildings: Buildings
var _structures: Structures
var _flights: Flights
var _perches: Perches
# Every crouch and jump in flight, by enemy id.
var _jumps: Dictionary[int, Jump] = {}
# The ticks left on each jumper's cooldown, by enemy id; a jumper not listed is ready.
var _cooldowns: Dictionary[int, int] = {}
# Where each jumper that landed on the ground within the fall-back window crouched, and the ticks
# left in its window, by enemy id.
var _landed_from: Dictionary[int, Vector2] = {}
var _landed_ticks: Dictionary[int, int] = {}
# The wall cells jumps crossed this tick, each with its jump's ground cell, in the order crossed.
var _knock_offs: Array[Overflow.KnockOff] = []


## One jumper's crouch and jump: the way it takes, fixed as the crouch starts, and how far through
## the crouch and the flight it is.
class Jump:
	extends RefCounted

	## The planned way: its cells and their centres, ending where it lands, whether it perches,
	## and [member Overflow.Tumble.from], where it crouched.
	var way: Overflow.Tumble
	## Crouch ticks still to go; 0 once in the air.
	var crouch_left := 0
	## Ticks flown so far, out of [member air_ticks].
	var flown := 0
	## How many ticks the flight takes, fixed as the crouch starts.
	var air_ticks := 1
	## How far it moves along its way each tick in the air.
	var step := 0.0

	func _init(planned: Overflow.Tumble, crouch_ticks: int, flight_ticks: int) -> void:
		way = planned
		crouch_left = crouch_ticks
		air_ticks = flight_ticks

	## True while it is still crouching.
	func is_crouching() -> bool:
		return crouch_left > 0 or flown == 0


func _init(
	run_settings: Settings,
	run_map: MapData,
	run_structures: Structures,
	run_buildings: Buildings,
	run_enemies: Enemies,
	run_routing: Routing,
	run_perches: Perches,
) -> void:
	_settings = run_settings
	_structures = run_structures
	_buildings = run_buildings
	_enemies = run_enemies
	_perches = run_perches
	_flights = Flights.new(
		run_settings, run_map, run_structures, run_enemies, run_routing, run_perches
	)


## From [method Enemies.move], where the jumper at [param index] would take a structure target:
## starts it crouching if it is ready and a jump over is planned. False, changing nothing, when it
## isn't a jumper, is on cooldown, or the barrier is too thick, the base full or there is nowhere
## to land; it then attacks as any enemy.
func try_start(index: int) -> bool:
	if _enemies.kinds[index] != Enemies.Kind.JUMPER:
		return false
	if _enemies.states[index] != Enemies.State.WALKING:
		return false
	var id := _enemies.ids[index]
	if _cooldowns.has(id) or _jumps.has(id):
		return false
	var way := _flights.plan_jump(index, _settings.jumper_reach)
	if way == null:
		return false
	way.from = _enemies.positions[index]
	way.last_cell = Vector2i(way.from.floor())
	_jumps[id] = Jump.new(way, _settings.jumper_crouch_ticks, _settings.jumper_air_ticks)
	_landed_from.erase(id)
	_landed_ticks.erase(id)
	_enemies.set_state(index, Enemies.State.CROUCHING)
	return true


## At [constant Simulation.Step.MOVE_ENEMIES], after the overflow: cooldowns count down, crouches
## count down and lift off, and jumps in flight move and land. The dead stay where they fell until
## removal, then give back any room they claimed.
func step() -> void:
	_knock_offs.clear()
	_count_down()
	for id: int in _jumps.keys():
		var jump: Jump = _jumps[id]
		var i := _enemies.index_of(id)
		if i == Enemies.NONE:
			if jump.way.perching:
				_perches.release_claim(jump.way.target)
			_jumps.erase(id)
			continue
		if not _enemies.is_alive(i):
			continue
		if jump.crouch_left > 0:
			jump.crouch_left -= 1
			continue
		if jump.flown == 0:
			_lift_off(i, jump)
		_fly(i, jump)
		if not _enemies.is_alive(i) or jump.flown < jump.air_ticks:
			continue
		_jumps.erase(id)
		_cooldowns[id] = _settings.jumper_cooldown_ticks
		if jump.way.perching and _flights.perch(i, jump.way):
			continue
		_enemies.set_state(i, Enemies.State.WALKING)
		_landed_from[id] = jump.way.from
		_landed_ticks[id] = _settings.fall_back_window_ticks


## The wall cells jumps crossed this tick, each with its ground cell, for the knock-off at
## [constant Simulation.Step.MOVE_UNITS].
func take_knock_offs() -> Array[Overflow.KnockOff]:
	var taken := _knock_offs
	_knock_offs = []
	return taken


## At [constant Simulation.Step.REMOVE_DEAD], the body of each jumper in [param deaths] killed in
## the air, or within the fall-back window of landing on the ground, falls back to where it
## crouched.
func fall_back(deaths: Deaths) -> void:
	if not _settings.bodies_fall_back:
		return
	for k in deaths.size():
		var id := deaths.ids[k]
		var jump: Jump = _jumps.get(id)
		if jump != null and not jump.is_crouching():
			deaths.bodies[k] = jump.way.from
		elif _landed_from.has(id):
			deaths.bodies[k] = _landed_from[id]


## The crouch or jump of the enemy with id [param id], for the view, or null.
func jump(id: int) -> Jump:
	return _jumps.get(id)


## The ticks left on the cooldown of the jumper with id [param id]: 0 when it is ready.
func cooldown(id: int) -> int:
	return _cooldowns.get(id, 0)


func _count_down() -> void:
	for id: int in _cooldowns.keys():
		var left := _cooldowns[id] - 1
		if left <= 0 or _enemies.index_of(id) == Enemies.NONE:
			_cooldowns.erase(id)
		else:
			_cooldowns[id] = left
	# The window closes early once the jumper stops walking: a tumble or perch since has its own
	# rule for where the body lands.
	for id: int in _landed_ticks.keys():
		var left := _landed_ticks[id] - 1
		var index := _enemies.index_of(id)
		var walking := index != Enemies.NONE and _enemies.states[index] == Enemies.State.WALKING
		if left <= 0 or not walking:
			_landed_ticks.erase(id)
			_landed_from.erase(id)
		else:
			_landed_ticks[id] = left


# The jumper at [param i] leaves the ground from where it crouched, at the speed that covers its
# way in its air time.
func _lift_off(i: int, jump: Jump) -> void:
	_enemies.set_state(i, Enemies.State.JUMPING)
	var way := jump.way
	way.from = _enemies.positions[i]
	way.last_cell = Vector2i(way.from.floor())
	var length := 0.0
	var previous := way.from
	for point in way.path:
		length += previous.distance_to(point)
		previous = point
	jump.step = length / jump.air_ticks


# Moves the jumper at [param i] a tick along its way, ignoring slow, collision and structures,
# landing exactly on its way's end on the last tick. Each wall cell it enters is recorded for the
# knock-off, and each cell it enters is ground by a working grinder there.
func _fly(i: int, jump: Jump) -> void:
	jump.flown += 1
	var way := jump.way
	var budget := INF if jump.flown >= jump.air_ticks else jump.step
	var pos := _enemies.positions[i]
	while budget > 0.0 and way.next < way.path.size():
		var target := way.path[way.next]
		var gap := pos.distance_to(target)
		if gap > budget:
			pos += (target - pos) / gap * budget
			budget = 0.0
		else:
			pos = target
			budget -= gap
			way.next += 1
		var cell := Vector2i(pos.floor())
		if cell != way.last_cell:
			way.last_cell = cell
			if _structures.structure_at(cell) == Structures.Kind.WALL:
				_knock_offs.append(Overflow.KnockOff.new(cell, way.ground()))
			_buildings.grind_tumble(_enemies, i, cell)
			if not _enemies.is_alive(i):
				break
	_enemies.positions[i] = pos
