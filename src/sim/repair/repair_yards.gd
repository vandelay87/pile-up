class_name RepairYards
extends RefCounted

## One drone per repair yard. During a wave, while its yard is powered, a drone flies in a straight
## line from the yard's centre to a damaged building in the yard's repair area, repairs it to full
## and flies home. Drones are never attacked and ignore terrain; they step in their yards' build
## order, so ties are deterministic.

enum State { HOME, OUTBOUND, REPAIRING, RETURNING }

const NONE := -1
const NOT_A_YARD := "not a repair yard"
const NO_SUCH_BUILDING := "no such building"
const ITSELF := "a yard cannot repair itself"
const OUTSIDE_AREA := "outside the repair area"
# Float slack for arriving (Vector2 is single precision), so 60 steps of 8/60 cover 8 cells in
# exactly 60 ticks.
const _ARRIVE_SLACK := 1e-4

## The drones in their yards' build order.
var drones: Array[Drone] = []

var _settings: Settings
var _buildings: Buildings
var _by_yard: Dictionary[int, Drone] = {}


class Drone:
	extends RefCounted

	var yard_id: int
	var home: Vector2
	var state := State.HOME
	var position: Vector2
	## The building it is flying to or repairing, or NONE.
	var target_id := NONE
	## The building the player assigned, or NONE for auto.
	var assignment := NONE
	## HP this yard's drone has repaired this run.
	var repaired := 0.0

	func _init(yard: Buildings.Building) -> void:
		yard_id = yard.id
		home = yard.centre
		position = home

	func is_on_job() -> bool:
		return state == State.OUTBOUND or state == State.REPAIRING


func _init(run_settings: Settings, run_buildings: Buildings) -> void:
	_settings = run_settings
	_buildings = run_buildings


## The square reaching the repair area in cells from a yard's footprint's edge (not clipped).
static func repair_area_of(origin: Vector2i, reach: int) -> Rect2i:
	return Rect2i(origin, Buildings.footprint_size(Buildings.REPAIR_YARD)).grow(reach)


## Creates a new yard's drone, at home.
func add(yard: Buildings.Building) -> void:
	var created := Drone.new(yard)
	drones.append(created)
	_by_yard[yard.id] = created


func drone(yard_id: int) -> Drone:
	return _by_yard.get(yard_id, null)


func repair_area(yard: Buildings.Building) -> Rect2i:
	return repair_area_of(yard.origin, _settings.repair_area)


## Whether any of a building's cells lies in the yard's repair area.
func is_in_area(yard: Buildings.Building, other: Buildings.Building) -> bool:
	var footprint := Rect2i(other.origin, Buildings.footprint_size(other.kind))
	return repair_area(yard).intersects(footprint)


## Sets a yard's assignment, or returns the reason it was rejected. It takes effect once the
## drone is home from its current trip.
func assign(yard_id: int, building_id: int) -> String:
	var yard_drone := drone(yard_id)
	if yard_drone == null:
		return NOT_A_YARD
	var other := _buildings.building(building_id)
	if other == null:
		return NO_SUCH_BUILDING
	if building_id == yard_id:
		return ITSELF
	if not is_in_area(_buildings.building(yard_id), other):
		return OUTSIDE_AREA
	yard_drone.assignment = building_id
	return ""


## Clears a yard's assignment, or returns the reason it was rejected.
func clear(yard_id: int) -> String:
	var yard_drone := drone(yard_id)
	if yard_drone == null:
		return NOT_A_YARD
	yard_drone.assignment = NONE
	return ""


## Flies every drone one tick and repairs. Outside a wave, or while its yard is unpowered, a drone
## flies home and stops. A destroyed yard's drone is gone.
func step(in_wave: bool) -> void:
	var gone := false
	for drone in drones:
		var yard := _buildings.building(drone.yard_id)
		if yard == null:
			_by_yard.erase(drone.yard_id)
			gone = true
			continue
		if drone.assignment != NONE and _buildings.building(drone.assignment) == null:
			drone.assignment = NONE
		if not (in_wave and yard.powered):
			_send_home(drone)
		elif drone.state == State.HOME:
			_pick(drone, yard)
		elif drone.is_on_job() and _buildings.building(drone.target_id) == null:
			if not _pick(drone, yard):
				_send_home(drone)
		_advance(drone)
	# Drones on one building all leave on the tick it is full, whichever of them topped it up.
	for drone in drones:
		if drone.state == State.REPAIRING:
			var target := _buildings.building(drone.target_id)
			if target != null and not _buildings.is_damaged(target):
				_send_home(drone)
	if gone:
		drones = drones.filter(func(drone: Drone) -> bool: return _by_yard.has(drone.yard_id))


func _advance(drone: Drone) -> void:
	match drone.state:
		State.OUTBOUND:
			if _fly(drone, _buildings.building(drone.target_id).centre):
				drone.state = State.REPAIRING
		State.REPAIRING:
			var target := _buildings.building(drone.target_id)
			drone.repaired += _buildings.repair(target.id, _settings.repair_per_tick)
		State.RETURNING:
			if _fly(drone, drone.home):
				drone.state = State.HOME


## Moves a drone one step towards a point; true when it arrives.
func _fly(drone: Drone, to: Vector2) -> bool:
	var step := _settings.drone_step
	if drone.position.distance_to(to) <= step + _ARRIVE_SLACK:
		drone.position = to
		return true
	drone.position = drone.position.move_toward(to, step)
	return false


func _send_home(drone: Drone) -> void:
	drone.target_id = NONE
	if drone.state != State.HOME:
		drone.state = State.RETURNING


## Picks a job: the assignment when it is damaged, otherwise the nearest candidate (then lowest HP,
## then lowest id), preferring one no other drone is on. False when there is nothing to repair.
func _pick(drone: Drone, yard: Buildings.Building) -> bool:
	var assigned := _buildings.building(drone.assignment)
	if assigned != null and _buildings.is_damaged(assigned):
		_start_job(drone, assigned.id)
		return true
	var taken := {}
	for other in drones:
		if other != drone and other.is_on_job():
			taken[other.target_id] = true
	var best: Buildings.Building = null
	var best_taken := true
	for candidate in _buildings.built:
		if candidate.id == yard.id or not _buildings.is_damaged(candidate):
			continue
		if not is_in_area(yard, candidate):
			continue
		var is_taken := taken.has(candidate.id)
		if best == null or _is_better(yard, candidate, is_taken, best, best_taken):
			best = candidate
			best_taken = is_taken
	if best == null:
		return false
	_start_job(drone, best.id)
	return true


func _is_better(
	yard: Buildings.Building,
	candidate: Buildings.Building,
	is_taken: bool,
	best: Buildings.Building,
	best_taken: bool,
) -> bool:
	if is_taken != best_taken:
		return not is_taken
	var distance := yard.centre.distance_to(candidate.centre)
	var best_distance := yard.centre.distance_to(best.centre)
	if distance != best_distance:
		return distance < best_distance
	if candidate.hp != best.hp:
		return candidate.hp < best.hp
	return candidate.id < best.id


func _start_job(drone: Drone, target_id: int) -> void:
	drone.target_id = target_id
	drone.state = State.OUTBOUND
