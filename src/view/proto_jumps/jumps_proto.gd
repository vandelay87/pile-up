extends Node

## PROTOTYPE, throwaway: wayfinder ticket "Feel: jumps and tumbles onto buildings" (#236).
## Lives only on the prototype/v5-jumps branch and is never merged. It runs the real game
## (main.tscn) and fakes v5's jumper and perching over it, to judge by feel: the arc and length
## of a jump against a tumble, how a perched enemy reads on its building, the jumper's reach and
## cooldown, and whether jumpers should come in groups.
##
## Fakes, poked into the sim inside its tick (so pause and speed apply):
## - A jumper is a normal enemy marked here, forced onto the direct route. It's flagged as
##   tumbling while it crouches, jumps or is perched, so the sim doesn't walk or collide it.
## - A jump follows docs/design.md's rule: over the wall or building it touches facing the base,
##   at most [reach] wall/building cells, perched on the first building (or the base) with room,
##   else on the first free cell beyond. Then a cooldown.
## - An overflow tumble crossing a building with room is taken off Overflow and perched there.
## - A perched enemy attacks its building at the usual damage and drops when it falls; killed,
##   its body drops back where its jump or tumble started.
## Left out: jumper speed, knock-offs, grinders on perched enemies, bloaters perching.

const MAIN_SCENE := preload("res://src/view/main.tscn")
const NONE_CELL := Vector2i(-1, -1)
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]
const JUMP_STYLES := [
	{"name": "Hop", "crouch": 0.12, "air": 0.45, "arc": 10.0},
	{"name": "High arc", "crouch": 0.25, "air": 0.8, "arc": 24.0},
	{"name": "Pounce", "crouch": 0.4, "air": 0.3, "arc": 4.0},
]
const TUMBLE_STYLES := [
	"as now: raised flat, orange",
	"low fall: up over the top, drop",
	"low fall, no orange",
]
const PERCH_STYLES := [
	"just standing on the roof",
	"roof + red marker overhead",
	"roof + attack bob",
]
const JUMPER_TINT := Color(0.7, 0.45, 1.0)
const PERCHED_TINT := Color(1.0, 0.35, 0.55)
const SHADOW := Color(0, 0, 0, 0.35)
const MARKER := Color(1.0, 0.2, 0.25)
const PAINT := Color(1.0, 1.0, 1.0, 0.25)
## Pixels above the ground at a wall's top: 5 pile slabs.
const WALL_TOP := 5.0 * Atlas.PILE_SLAB_HEIGHT
const BASE_ROOF := 48.0
const FALL_BACK_TICKS := Simulation.TICKS_PER_SECOND

var _main: Main
var _sim: Simulation
var _renderer: EnemyRenderer
var _ground: Overlay
var _top: Overlay
var _readout := Label.new()
var _sliders: Dictionary[String, HSlider] = {}
var _style := 1
var _tumble_style := 1
var _perch_style := 0
var _tint_jumpers := true
var _shadows := true
var _perch_overflow := true
var _painting := false
var _paint_held := 0
var _paint_queue: Array[Vector2i] = []
var _erase_queue: Array[Vector2i] = []
var _send_queue: Array[int] = []

# Per run, reset by _hook.
var _seen_id := -1
var _group_left := 0
var _jumpers: Dictionary[int, bool] = {}
var _cooldowns: Dictionary[int, int] = {}
var _jumps: Dictionary[int, Jump] = {}
var _perched: Dictionary[int, Perch] = {}
var _landed_from: Dictionary[int, Vector2] = {}
var _landed_ticks: Dictionary[int, int] = {}
var _raised: Dictionary[int, bool] = {}
var _jumps_made := 0
var _perched_by_jump := 0
var _perched_by_tumble := 0
var _blocked := 0


class Jump:
	extends RefCounted
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var perch_cell := NONE_CELL
	var crouch_left := 0
	var air_ticks := 1
	var tick := 0
	var start_lift := 0.0
	var end_lift := 0.0
	## The lift at the top of the arc: the tallest thing crossed, plus the clearance.
	var peak := 0.0


class Perch:
	extends RefCounted
	var cell := Vector2i.ZERO
	var drop := Vector2.ZERO
	var since := 0


func _ready() -> void:
	process_priority = 100
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	_renderer = _main.get_node("EnemyRenderer") as EnemyRenderer
	_ground = Overlay.new()
	_ground.proto = self
	_ground.top = false
	_main.add_child(_ground)
	_main.move_child(_ground, _main.get_node("World").get_index())
	_top = Overlay.new()
	_top.proto = self
	_top.top = true
	_top.z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 1
	_main.add_child(_top)
	var input := InputSink.new()
	input.proto = self
	_main.add_child(input)
	_build_panel()
	_apply_style(_style)


func _process(_delta: float) -> void:
	if _main.simulation == null:
		return
	if _main.simulation != _sim:
		_hook(_main.simulation)
	_draw_enemies()
	_ground.queue_redraw()
	_top.queue_redraw()
	_readout.text = _state_text()


func _hook(sim: Simulation) -> void:
	_sim = sim
	_sim.step_observer = _on_step
	_seen_id = -1
	_group_left = 0
	_jumpers.clear()
	_cooldowns.clear()
	_jumps.clear()
	_perched.clear()
	_landed_from.clear()
	_landed_ticks.clear()
	_raised.clear()
	_jumps_made = 0
	_perched_by_jump = 0
	_perched_by_tumble = 0
	_blocked = 0


# --- sim side ---------------------------------------------------------------------------------


func _on_step(step: Simulation.Step) -> void:
	match step:
		Simulation.Step.DRAIN_COMMANDS:
			_paint_walls()
		Simulation.Step.SPAWN_ENEMIES:
			_send_jumpers()
		Simulation.Step.REBUILD_SPATIAL_HASH:
			_mark_new_enemies()
			_force_direct()
		Simulation.Step.MOVE_UNITS:
			_count_down()
			_advance_jumps()
			_hold_perched()
			_capture_tumbles()
			_start_jumps()
		Simulation.Step.REMOVE_DEAD:
			_place_bodies()


# Walls painted by hand land as five bodies on the cell, through the piles' own landing.
func _paint_walls() -> void:
	var piles := _sim.piles
	for cell in _paint_queue:
		if (
			not _sim.map.in_bounds(cell)
			or _sim.structures.structure_at(cell) != Structures.Kind.NONE
		):
			continue
		if _sim.map.rock[_sim.map.index_of(cell)] == 1:
			continue
		for _k in Piles.WALL_LEVEL - piles.level(cell):
			piles._queued.append(MapData.centre_of(cell))
	_paint_queue.clear()
	for cell in _erase_queue:
		if _sim.map.in_bounds(cell):
			piles.erase(cell)
	_erase_queue.clear()


func _send_jumpers() -> void:
	var edges := _sim.map.spawn_edges
	for size in _send_queue:
		var together := size > 1
		var edge := edges[randi() % edges.size()]
		var cells := _sim.map.spawn_cells(edge)
		var anchor := cells[randi() % cells.size()]
		for _k in absi(size):
			if not together:
				edge = edges[randi() % edges.size()]
				cells = _sim.map.spawn_cells(edge)
				anchor = cells[randi() % cells.size()]
			var jitter := Vector2(randf_range(-0.8, 0.8), randf_range(-0.8, 0.8))
			var pos := MapData.centre_of(anchor) + jitter
			if not _sim.map.in_bounds(Vector2i(pos.floor())):
				pos = MapData.centre_of(anchor)
			var id := _sim.enemies.spawn(pos, _sim.settings.enemy_hp)
			_jumpers[id] = true
	_send_queue.clear()


# Wave spawns become jumpers at the jumper share, alone or in a group of the next spawns.
func _mark_new_enemies() -> void:
	var enemies := _sim.enemies
	var share := _value("share") / 100.0
	var group := int(_value("group"))
	for i in enemies.count:
		var id := enemies.ids[i]
		if id <= _seen_id:
			continue
		_seen_id = maxi(_seen_id, id)
		if enemies.kinds[i] != Enemies.Kind.NORMAL or _jumpers.has(id):
			continue
		if _group_left > 0:
			_group_left -= 1
			_jumpers[id] = true
		elif randf() < share / group:
			_jumpers[id] = true
			_group_left = group - 1


func _force_direct() -> void:
	var enemies := _sim.enemies
	for id: int in _jumpers.keys():
		var i := enemies.index_of(id)
		if i == Enemies.NONE:
			_forget(id)
			continue
		if enemies.tumbling[i] == 0:
			enemies.routes[i] = Routing.Route.DIRECT


func _count_down() -> void:
	for id: int in _cooldowns.keys():
		_cooldowns[id] -= 1
		if _cooldowns[id] <= 0:
			_cooldowns.erase(id)
	for id: int in _landed_ticks.keys():
		_landed_ticks[id] -= 1
		if _landed_ticks[id] <= 0:
			_landed_ticks.erase(id)
			_landed_from.erase(id)


func _advance_jumps() -> void:
	var enemies := _sim.enemies
	for id: int in _jumps.keys():
		var i := enemies.index_of(id)
		if i == Enemies.NONE or not enemies.is_alive(i):
			continue
		var jump: Jump = _jumps[id]
		if jump.crouch_left > 0:
			jump.crouch_left -= 1
			continue
		jump.tick += 1
		var f := minf(float(jump.tick) / jump.air_ticks, 1.0)
		enemies.positions[i] = jump.from.lerp(jump.to, f)
		if f < 1.0:
			continue
		_jumps.erase(id)
		if jump.perch_cell != NONE_CELL:
			_perch(id, jump.perch_cell, jump.from)
			_perched_by_jump += 1
		else:
			enemies.land(i)
			enemies.routes[i] = Routing.Route.DIRECT
			_landed_from[id] = jump.from
			_landed_ticks[id] = FALL_BACK_TICKS
		_cooldowns[id] = int(_value("cooldown") * Simulation.TICKS_PER_SECOND)


func _perch(id: int, cell: Vector2i, drop: Vector2) -> void:
	var perch := Perch.new()
	perch.cell = cell
	perch.drop = drop
	perch.since = _sim.tick_count
	_perched[id] = perch


# Perched enemies attack what they stand on, and drop where they are once it falls.
func _hold_perched() -> void:
	var enemies := _sim.enemies
	var structures := _sim.structures
	var damage := _sim.settings.structure_damage_per_tick
	for id: int in _perched.keys():
		var i := enemies.index_of(id)
		if i == Enemies.NONE:
			_perched.erase(id)
			continue
		if not enemies.is_alive(i):
			continue
		var perch: Perch = _perched[id]
		var kind := structures.structure_at(perch.cell)
		if kind == Structures.Kind.BUILDING or kind == Structures.Kind.BASE:
			structures.damage(perch.cell, damage)
			continue
		_perched.erase(id)
		enemies.land(i)
		if _jumpers.has(id):
			enemies.routes[i] = Routing.Route.DIRECT


# Overflow tumbles crossing a building with room stop on it.
func _capture_tumbles() -> void:
	if not _perch_overflow:
		return
	var overflow := _sim.overflow
	var enemies := _sim.enemies
	for id: int in overflow._tumbles.keys():
		var i := enemies.index_of(id)
		if i == Enemies.NONE or not enemies.is_alive(i):
			continue
		if enemies.kinds[i] == Enemies.Kind.BLOATER:
			continue
		var cell := Vector2i(enemies.positions[i].floor())
		if _sim.structures.structure_at(cell) != Structures.Kind.BUILDING or not _has_room(cell):
			continue
		var tumble: Overflow.Tumble = overflow._tumbles[id]
		overflow._tumbles.erase(id)
		enemies.positions[i] = _spot_in(cell)
		_perch(id, cell, tumble.from)
		_perched_by_tumble += 1


func _start_jumps() -> void:
	var enemies := _sim.enemies
	_blocked = 0
	for id: int in _jumpers.keys():
		if _jumps.has(id) or _perched.has(id) or _cooldowns.has(id):
			continue
		var i := enemies.index_of(id)
		if i == Enemies.NONE or not enemies.is_alive(i) or enemies.tumbling[i] == 1:
			continue
		var jump := _plan_jump(i)
		if jump == null:
			continue
		enemies.start_tumble(i)
		_jumps[id] = jump
		_jumps_made += 1


# Over the wall or building it touches that faces most towards the base, crossing at most
# [reach] cells of them: perched on the first building or base cell with room, else on the
# first free, uncrowded cell beyond.
func _plan_jump(i: int) -> Jump:
	var enemies := _sim.enemies
	var map := _sim.map
	var structures := _sim.structures
	var pos := enemies.positions[i]
	var cell := Vector2i(pos.floor())
	var heading := _sim.routing.sample_direction(Routing.Route.DIRECT, pos)
	var reach := _sim.settings.separation_radius + _sim.settings.wall_reach
	var best := Vector2i.ZERO
	var best_facing := 0.0
	for offset in NEIGHBOURS:
		var touched := cell + offset
		if not map.in_bounds(touched):
			continue
		var touched_index := map.index_of(touched)
		if not structures.is_breakable(touched_index) and not structures.is_base(touched_index):
			continue
		if Overflow._distance_to_square(pos, touched) > reach:
			continue
		var facing := Vector2(offset).normalized().dot(heading)
		if facing > best_facing:
			best_facing = facing
			best = offset
	if best == Vector2i.ZERO:
		return null
	var max_cells := int(_value("reach"))
	var crossed := 0
	var top := 0.0
	var at := cell + best
	for _step in max_cells + 4:
		if not map.in_bounds(at):
			break
		var index := map.index_of(at)
		if map.rock[index] == 1:
			break
		var kind := structures.structure_at(at)
		if kind == Structures.Kind.BASE:
			if _has_room(at):
				return _new_jump(pos, _spot_in(at), at, top)
			break
		if kind == Structures.Kind.BUILDING or kind == Structures.Kind.WALL:
			crossed += 1
			if crossed > max_cells:
				break
			if kind == Structures.Kind.BUILDING and _has_room(at):
				return _new_jump(pos, _spot_in(at), at, top)
			top = maxf(top, WALL_TOP if kind == Structures.Kind.WALL else _roof(at))
		elif enemies.count_in_cell(index) < _sim.settings.landing_crowd:
			return _new_jump(pos, _spot_in(at), NONE_CELL, top)
		else:
			top = maxf(top, _renderer._lift_at(MapData.centre_of(at)))
		at += best
	_blocked += 1
	return null


func _new_jump(from: Vector2, to: Vector2, perch_cell: Vector2i, top: float) -> Jump:
	var jump := Jump.new()
	jump.from = from
	jump.to = to
	jump.perch_cell = perch_cell
	jump.crouch_left = int(_value("crouch") * Simulation.TICKS_PER_SECOND)
	jump.air_ticks = maxi(int(_value("air") * Simulation.TICKS_PER_SECOND), 1)
	jump.start_lift = _renderer._lift_at(from)
	jump.end_lift = _roof(perch_cell) if perch_cell != NONE_CELL else _renderer._lift_at(to)
	jump.peak = maxf(top, maxf(jump.start_lift, jump.end_lift)) + _value("arc")
	return jump


func _spot_in(cell: Vector2i) -> Vector2:
	return MapData.centre_of(cell) + Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))


# Room for one more perched enemy on the building or base at [param cell].
func _has_room(cell: Vector2i) -> bool:
	var room := int(_value("room"))
	if room <= 0:
		return false
	var kind := _sim.structures.structure_at(cell)
	if kind == Structures.Kind.BASE:
		var base := _sim.map.base
		return _count_perched_in(base) < room * base.get_area()
	var id := _sim.occupancy.building_at(cell)
	var building := _sim.buildings.building(id)
	if building == null:
		return false
	var count := 0
	for perch: Perch in _perched.values():
		if _sim.occupancy.building_at(perch.cell) == id:
			count += 1
	for jump: Jump in _jumps.values():
		if jump.perch_cell != NONE_CELL and _sim.occupancy.building_at(jump.perch_cell) == id:
			count += 1
	return count < room * building.footprint.size()


func _count_perched_in(area: Rect2i) -> int:
	var count := 0
	for perch: Perch in _perched.values():
		if area.has_point(perch.cell):
			count += 1
	for jump: Jump in _jumps.values():
		if jump.perch_cell != NONE_CELL and area.has_point(jump.perch_cell):
			count += 1
	return count


# Bodies of jumpers killed mid-jump or just after landing, and of perched enemies, fall back
# where their jump or tumble started.
func _place_bodies() -> void:
	var enemies := _sim.enemies
	for i in enemies.count:
		if enemies.is_alive(i):
			continue
		var id := enemies.ids[i]
		if _perched.has(id):
			enemies.positions[i] = _perched[id].drop
		elif _jumps.has(id):
			enemies.positions[i] = _jumps[id].from
		elif _landed_from.has(id):
			enemies.positions[i] = _landed_from[id]


func _forget(id: int) -> void:
	_jumpers.erase(id)
	_jumps.erase(id)
	_perched.erase(id)
	_cooldowns.erase(id)
	_landed_from.erase(id)
	_landed_ticks.erase(id)


# --- view side --------------------------------------------------------------------------------


# Runs after EnemyRenderer, overriding the look of jumpers, jumps, perched enemies and tumbles.
# Each overridden item gets its renderer scale cleared, so the renderer redraws it afresh next
# frame once it's ordinary again.
func _draw_enemies() -> void:
	var enemies := _sim.enemies
	var now := Time.get_ticks_msec() / 1000.0
	var raised: Dictionary[int, bool] = {}
	for id: int in _jumpers.keys():
		var i := enemies.index_of(id)
		if i == Enemies.NONE or i >= _renderer._items.size():
			continue
		if _jumps.has(id) or _perched.has(id):
			continue
		if _tint_jumpers and enemies.tumbling[i] == 0:
			_set_look(i, JUMPER_TINT, _renderer._lift_at(enemies.positions[i]), Vector2.ONE)
	for id: int in _jumps.keys():
		var i := enemies.index_of(id)
		if i == Enemies.NONE or i >= _renderer._items.size():
			continue
		var jump: Jump = _jumps[id]
		var tint := JUMPER_TINT if _tint_jumpers else EnemyRenderer.TINT
		if jump.crouch_left > 0:
			_set_look(i, tint, jump.start_lift, Vector2(1.3, 0.65))
			continue
		var f := clampf(float(jump.tick) / jump.air_ticks, 0.0, 1.0)
		# A parabola through the start, the peak at halfway and the end, so the arc only clears
		# what's in the way, never a fixed height.
		var line := lerpf(jump.start_lift, jump.end_lift, f)
		var rise := maxf(jump.peak - lerpf(jump.start_lift, jump.end_lift, 0.5), 0.0)
		var lift := line + rise * 4.0 * f * (1.0 - f)
		var stretch := Vector2(0.85, 1.2) if f < 0.4 else Vector2.ONE
		_set_look(i, tint, lift, stretch)
		_raise(i, raised)
	for id: int in _perched.keys():
		var i := enemies.index_of(id)
		if i == Enemies.NONE or i >= _renderer._items.size():
			continue
		var perch: Perch = _perched[id]
		var lift := _roof(perch.cell)
		if _perch_style == 2:
			lift += absf(sin(now * 9.0 + id)) * 4.0
		var tint := JUMPER_TINT if _jumpers.has(id) and _tint_jumpers else PERCHED_TINT
		_set_look(i, tint, lift, Vector2.ONE)
		_raise(i, raised)
	if _tumble_style > 0:
		for id: int in _sim.overflow._tumbles.keys():
			var i := enemies.index_of(id)
			if i == Enemies.NONE or i >= _renderer._items.size():
				continue
			var tumble: Overflow.Tumble = _sim.overflow._tumbles[id]
			var end := tumble.path[tumble.path.size() - 1]
			var total := maxf(tumble.from.distance_to(end), 0.01)
			var f := clampf(tumble.from.distance_to(enemies.positions[i]) / total, 0.0, 1.0)
			var ground := _renderer._lift_at(enemies.positions[i])
			var lift := maxf(ground, (WALL_TOP + 6.0) * sin(PI * minf(f * 1.6, 1.0)))
			if f > 0.62:
				lift = lerpf(WALL_TOP + 6.0, ground, (f - 0.62) / 0.38)
			var tint := EnemyRenderer.TUMBLE_TINT if _tumble_style == 1 else _renderer._tint(i)
			_set_look(i, tint, lift, Vector2(1.1, 0.9))
	for i: int in _raised.keys():
		if not raised.has(i) and i < _renderer._items.size():
			RenderingServer.canvas_item_set_z_index(_renderer._items[i], 0)
	_raised = raised


func _set_look(i: int, tint: Color, lift: float, scale: Vector2) -> void:
	RenderingServer.canvas_item_set_modulate(_renderer._items[i], tint)
	RenderingServer.canvas_item_set_transform(
		_renderer._sprites[i], Transform2D(0.0, scale, 0.0, Vector2(0, -lift))
	)
	_renderer._scales[i] = 0.0


func _raise(i: int, raised: Dictionary[int, bool]) -> void:
	raised[i] = true
	if not _raised.has(i):
		RenderingServer.canvas_item_set_z_index(_renderer._items[i], 1)


# Pixels above the ground of the roof over [param cell]: the building sprite's height less
# its footprint's diamond, or the base's.
func _roof(cell: Vector2i) -> float:
	if _sim.structures.structure_at(cell) == Structures.Kind.BASE:
		return BASE_ROOF
	var building := _sim.buildings.building(_sim.occupancy.building_at(cell))
	if building == null or not TowerView.REGIONS.has(building.kind):
		return WALL_TOP
	var size: Vector2i = TowerView.REGIONS[building.kind][1]
	var footprint := Buildings.footprint_size(building.kind)
	return size.y * Atlas.UNIT.y - Atlas.UNIT.y - (footprint.x + footprint.y) * Atlas.UNIT.y / 4.0


func draw_overlay(canvas: Overlay) -> void:
	if _sim == null:
		return
	var enemies := _sim.enemies
	if not canvas.top:
		if _shadows:
			for id: int in _jumps.keys():
				var i := enemies.index_of(id)
				if i == Enemies.NONE or _jumps[id].crouch_left > 0:
					continue
				var foot := GridTransform.grid_to_world(enemies.positions[i])
				canvas.draw_set_transform(foot, 0.0, Vector2(1.0, 0.5))
				canvas.draw_circle(Vector2.ZERO, 7.0, SHADOW)
				canvas.draw_set_transform(Vector2.ZERO)
		if _painting:
			var cell := _mouse_cell()
			var points := PackedVector2Array()
			for corner: Vector2i in [
				Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)
			]:
				points.append(GridTransform.grid_to_world(Vector2(cell + corner)))
			canvas.draw_colored_polygon(points, PAINT)
		return
	if _perch_style == 1:
		for id: int in _perched.keys():
			var i := enemies.index_of(id)
			if i == Enemies.NONE:
				continue
			var head := GridTransform.grid_to_world(enemies.positions[i])
			head.y -= _roof(_perched[id].cell) + 32.0
			var arrow := PackedVector2Array(
				[head + Vector2(-5, -7), head + Vector2(5, -7), head + Vector2(0, 0)]
			)
			canvas.draw_colored_polygon(arrow, MARKER)


# --- input and panel --------------------------------------------------------------------------


func handle_input(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		match key.keycode:
			KEY_F5:
				_apply_style((_style + 1) % JUMP_STYLES.size())
			KEY_F6:
				_tumble_style = (_tumble_style + 1) % TUMBLE_STYLES.size()
			KEY_F7:
				_perch_style = (_perch_style + 1) % PERCH_STYLES.size()
			KEY_F8:
				_painting = not _painting
			KEY_J:
				_send_queue.append(-10)
			KEY_K:
				_send_queue.append(maxi(int(_value("group")), 2))
			_:
				return false
		return true
	if not _painting:
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT and button.button_index != MOUSE_BUTTON_RIGHT:
			return false
		_paint_held = button.button_index if button.pressed else 0
		_paint_at(_mouse_cell())
		return true
	if event is InputEventMouseMotion and _paint_held != 0:
		_paint_at(_mouse_cell())
		return true
	return false


func _paint_at(cell: Vector2i) -> void:
	if _paint_held == MOUSE_BUTTON_LEFT:
		_paint_queue.append(cell)
	elif _paint_held == MOUSE_BUTTON_RIGHT:
		_erase_queue.append(cell)


func _mouse_cell() -> Vector2i:
	var world := (
		_ground.get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
	)
	return Vector2i(GridTransform.world_to_grid(world).floor())


func _apply_style(style: int) -> void:
	_style = style
	var preset: Dictionary = JUMP_STYLES[style]
	for key: String in ["crouch", "air", "arc"]:
		_sliders[key].value = preset[key]


func _value(key: String) -> float:
	return _sliders[key].value


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.custom_minimum_size.x = 330
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_readout.add_theme_font_size_override("font_size", 12)
	column.add_child(_readout)
	var styles := HBoxContainer.new()
	column.add_child(styles)
	for k in JUMP_STYLES.size():
		_button(styles, str(JUMP_STYLES[k]["name"]), _apply_style.bind(k))
	_slider(column, "crouch", "Crouch (s)", 0.0, 0.8, 0.02)
	_slider(column, "air", "Air time (s)", 0.1, 1.5, 0.05)
	_slider(column, "arc", "Clearance over tallest (px)", 0.0, 60.0, 2.0)
	_slider(column, "reach", "Reach (wall/building cells)", 1.0, 6.0, 1.0, 3.0)
	_slider(column, "cooldown", "Cooldown (s)", 0.0, 12.0, 0.5, 4.0)
	_slider(column, "share", "Jumper share of wave (%)", 0.0, 60.0, 1.0, 10.0)
	_slider(column, "group", "Group size", 1.0, 12.0, 1.0, 1.0)
	_slider(column, "room", "Perch room per cell", 0.0, 6.0, 1.0, 2.0)
	var looks := HBoxContainer.new()
	column.add_child(looks)
	_button(
		looks,
		"Tumble look",
		func() -> void: _tumble_style = (_tumble_style + 1) % TUMBLE_STYLES.size()
	)
	_button(
		looks, "Perch look", func() -> void: _perch_style = (_perch_style + 1) % PERCH_STYLES.size()
	)
	var toggles := HBoxContainer.new()
	column.add_child(toggles)
	_check(toggles, "Tint jumpers", _tint_jumpers, func(on: bool) -> void: _tint_jumpers = on)
	_check(toggles, "Shadows", _shadows, func(on: bool) -> void: _shadows = on)
	_check(
		column,
		"Overflow tumbles perch",
		_perch_overflow,
		func(on: bool) -> void: _perch_overflow = on
	)
	var sends := HBoxContainer.new()
	column.add_child(sends)
	_button(sends, "Send 10 (J)", func() -> void: _send_queue.append(-10))
	_button(
		sends, "Send a group (K)", func() -> void: _send_queue.append(maxi(int(_value("group")), 2))
	)
	_button(sends, "Paint walls (F8)", func() -> void: _painting = not _painting)


func _button(parent: Control, text: String, pressed: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	parent.add_child(button)


func _check(parent: Control, text: String, on: bool, toggled: Callable) -> void:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = on
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(toggled)
	parent.add_child(check)


func _slider(
	parent: Control, key: String, text: String, low: float, high: float, step: float, start := 0.0
) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.custom_minimum_size.x = 190
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = start
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var show := func(value: float) -> void: label.text = "%s: %s" % [text, str(value)]
	slider.value_changed.connect(show)
	show.call(start)
	_sliders[key] = slider


func _state_text() -> String:
	var enemies := _sim.enemies
	var alive := 0
	var on_ground := 0
	for id: int in _jumpers.keys():
		var i := enemies.index_of(id)
		if i == Enemies.NONE or not enemies.is_alive(i):
			continue
		alive += 1
		if not _jumps.has(id) and not _perched.has(id):
			on_ground += 1
	var crouching := 0
	for jump: Jump in _jumps.values():
		if jump.crouch_left > 0:
			crouching += 1
	var on_base := _count_perched_in(_sim.map.base)
	var lines: Array[String] = [
		"PROTOTYPE: jumps and perching (#236)",
		"%s   speed x%d" % ["PAUSED" if _sim.paused else "running", _sim.speed],
		"Jump: %s  [F5]" % JUMP_STYLES[_style]["name"],
		"Tumble: %s  [F6]" % TUMBLE_STYLES[_tumble_style],
		"Perch: %s  [F7]" % PERCH_STYLES[_perch_style],
		(
			"Jumpers alive %d: ground %d, crouch %d, air %d, perched %d"
			% [alive, on_ground, crouching, _jumps.size() - crouching, _count_jumpers_perched()]
		),
		"  on cooldown %d   blocked by a thick barrier now %d" % [_cooldowns.size(), _blocked],
		(
			"Jumps %d: perched %d   tumbles perched %d"
			% [_jumps_made, _perched_by_jump, _perched_by_tumble]
		),
		(
			"Perched now %d (on base %d)   tumbles in flight %d"
			% [_perched.size(), on_base, _sim.overflow._tumbles.size()]
		),
		"Paint walls [F8]: %s  (left paints, right erases)" % ("ON" if _painting else "off"),
	]
	return "\n".join(lines)


func _count_jumpers_perched() -> int:
	var count := 0
	for id: int in _perched.keys():
		if _jumpers.has(id):
			count += 1
	return count


class Overlay:
	extends Node2D

	var proto: Node
	var top := false

	func _draw() -> void:
		proto.call(&"draw_overlay", self)


class InputSink:
	extends Node

	var proto: Node

	func _unhandled_input(event: InputEvent) -> void:
		if proto.call(&"handle_input", event):
			get_viewport().set_input_as_handled()
