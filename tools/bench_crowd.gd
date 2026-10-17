# Keeps a dense crowd of enemies in a ring around the base, with a ring of towers firing into it,
# for the benchmarks. It can field an army among them: soldiers in and around the ring, some on
# walls it raises, ORDER_GROUP of them sent across the ring through the crowd every ORDER_INTERVAL
# ticks, and those that die in it replaced.
class_name BenchCrowd
extends RefCounted

const INNER_RADIUS := 6.0
const OUTER_RADIUS := 14.0
const BASE_HP := 1_000_000_000.0
const TOWERS := 8
const TOWER_RADIUS := 10.0
const ARMY := 50
const ARMY_ON_WALLS := 10
const ARMY_INNER_RADIUS := INNER_RADIUS - 2.0
const ARMY_OUTER_RADIUS := OUTER_RADIUS + 2.0
const ORDER_GROUP := 10
const ORDER_INTERVAL := 120
# Spots tried for each soldier before field_army gives up on a full army.
const _TRIES_PER_SOLDIER := 100

## Where the ring's towers stand (or stood, once the crowd breaks them).
var tower_origins: Array[Vector2i] = []

var _sim: Simulation
var _rng := RandomNumberGenerator.new()
# The army draws from its own stream, so the crowd is the same with it or without it.
var _army_rng := RandomNumberGenerator.new()
var _orders_sent := 0
var _centre: Vector2


func _init(sim: Simulation, crowd_seed: int) -> void:
	_sim = sim
	_sim.run_state.base_hp = BASE_HP
	_rng.seed = crowd_seed
	_army_rng.seed = hash([crowd_seed, "army"])
	_centre = Vector2(sim.map.base.get_center())
	_sim.run_state.add_gold(TOWERS * _sim.settings.tower_cost)
	for k in TOWERS:
		var centre := _centre + Vector2.from_angle(TAU * k / TOWERS) * TOWER_RADIUS
		var origin := Buildings.origin_at(Buildings.TOWER, centre)
		tower_origins.append(origin)
		_sim.queue_command(Commands.Build.new(Buildings.TOWER, origin))
	_sim.tick()
	# The towers re-settle the fields over a few ticks. A crowd arriving before they swap in
	# would follow fields that run through the towers and attack them all at once.
	while _sim.routing.is_settling():
		_sim.tick()


static func digest(sim: Simulation) -> int:
	var enemies := sim.enemies
	var soldiers := sim.soldiers
	return hash(
		[
			enemies.count,
			enemies.ids.slice(0, enemies.count),
			enemies.positions.slice(0, enemies.count),
			enemies.hp.slice(0, enemies.count),
			sim.piles.levels,
			soldiers.count,
			soldiers.ids.slice(0, soldiers.count),
			soldiers.positions.slice(0, soldiers.count),
			soldiers.hp.slice(0, soldiers.count),
			soldiers.targets.slice(0, soldiers.count),
			soldiers.kills.slice(0, soldiers.count),
		]
	)


func top_up(target: int) -> void:
	while _sim.enemies.count < target:
		_sim.enemies.spawn(_free_spot(), _sim.settings.enemy_hp)


func drop_body() -> void:
	_sim.piles.queue_bodies(Deaths.bodies_at(PackedVector2Array([_free_spot()])))


## Queues a wall's worth of bodies on a free spot in the crowd, returning its cell. They land
## next tick, unless the cell is taken.
func raise_wall() -> Vector2i:
	var spot := _free_spot()
	var bodies := PackedVector2Array()
	for n in Piles.WALL_LEVEL:
		bodies.append(spot)
	_sim.piles.queue_bodies(Deaths.bodies_at(bodies))
	return Vector2i(spot.floor())


## Raises [constant ARMY_ON_WALLS] walls in and around the ring and stands the army of
## [constant ARMY] there: a soldier on each wall that landed, the rest on the ground, each on a
## cell of its own. Ticks once, for the walls to land. Fields fewer when the ring runs out of
## free cells.
func field_army() -> void:
	var walls: Array[Vector2i] = []
	for n in ARMY_ON_WALLS:
		var spot := _army_spot()
		var bodies := PackedVector2Array()
		for body in Piles.WALL_LEVEL:
			bodies.append(spot)
		_sim.piles.queue_bodies(Deaths.bodies_at(bodies))
		walls.append(Vector2i(spot.floor()))
	_sim.tick()
	var taken := {}
	for cell in walls:
		var free := _sim.soldiers.can_stand_on(cell) and not taken.has(cell)
		if free and _sim.piles.level(cell) == Piles.WALL_LEVEL:
			taken[cell] = true
			_sim.soldiers.add(cell)
	_add_on_the_ground(taken)


## Stands a soldier on the ground in and around the ring for each one the army has lost, back up
## to [constant ARMY], each on a cell no soldier holds. Fields fewer when the ring runs out of
## free cells.
func top_up_army() -> void:
	if _sim.soldiers.count >= ARMY:
		return
	var taken := {}
	for i in _sim.soldiers.count:
		taken[_sim.soldiers.spot(i)] = true
	_add_on_the_ground(taken)


func _add_on_the_ground(taken: Dictionary) -> void:
	for attempt in ARMY * _TRIES_PER_SOLDIER:
		if _sim.soldiers.count == ARMY:
			return
		var cell := Vector2i(_army_spot().floor())
		var free := _sim.soldiers.can_stand_on(cell) and not taken.has(cell)
		if free and _sim.piles.level(cell) == 0:
			taken[cell] = true
			_sim.soldiers.add(cell)


## On every [constant ORDER_INTERVAL]-th tick [param t], sends the next [constant ORDER_GROUP]
## soldiers in turn on a Move across the ring, through the crowd, alternating Cluster and Line.
func send_army(t: int) -> void:
	if t % ORDER_INTERVAL != 0 or _sim.soldiers.count == 0:
		return
	var soldiers := _sim.soldiers
	var ids := PackedInt32Array()
	var mean := Vector2.ZERO
	for k in ORDER_GROUP:
		var i := (_orders_sent * ORDER_GROUP + k) % soldiers.count
		ids.append(soldiers.ids[i])
		mean += soldiers.positions[i] / ORDER_GROUP
	var edge := Vector2(_sim.map.width, _sim.map.height)
	var across := (2.0 * _centre - mean).clamp(Vector2.ZERO, edge)
	var formation := Formations.CLUSTER if _orders_sent % 2 == 0 else Formations.LINE
	_sim.queue_command(Commands.Move.new(ids, across, formation))
	_orders_sent += 1


func _free_spot() -> Vector2:
	return _spot_in(_rng, INNER_RADIUS, OUTER_RADIUS)


func _army_spot() -> Vector2:
	return _spot_in(_army_rng, ARMY_INNER_RADIUS, ARMY_OUTER_RADIUS)


# A point at a random angle and distance between [param inner] and [param outer] from the base's
# centre, on a clear cell of the map.
func _spot_in(rng: RandomNumberGenerator, inner: float, outer: float) -> Vector2:
	while true:
		var angle := rng.randf_range(0.0, TAU)
		var radius := rng.randf_range(inner, outer)
		var pos := _centre + Vector2.from_angle(angle) * radius
		var cell := Vector2i(pos.floor())
		if _sim.map.in_bounds(cell) and not _sim.map.is_rock(cell) and not _sim.map.is_base(cell):
			return pos
	return _centre
