extends Node

## PROTOTYPE, throwaway: wayfinder ticket "Directing units: selection and command feel" (#161).
## Lives only on the prototype/v4-unit-control branch and is never merged. It runs the real game
## (main.tscn) and lays v4 soldier control over it, to judge how selecting and ordering feel in
## the isometric camera among a dense swarm. Soldiers are view-side fakes that poke the sim
## directly: they move and fire inside the sim's tick (so pause and speed apply) and damage
## enemies with no building credit. No collision with enemies, no piles, no HP: other tickets.

const MAIN_SCENE := preload("res://src/view/main.tscn")
const SOLDIER_COUNT := 8
const SOLDIER_SPEED := 3.0
const SOLDIER_RANGE := 6.0
const SOLDIER_DAMAGE := 5.0
const SOLDIER_FIRE_RATE := 2.0
const FORMATION_SPACING := 0.8
const CLICK_SLOP := 6.0
const PICK_RADIUS := 18.0
const DOUBLE_TAP_MSEC := 350
const KEY_PAN_SPEED := 900.0
const EDGE_MARGIN := 10.0
const MARKER_MSEC := 450
const TRACER_MSEC := 70
const BOX_FILL := Color(0.4, 0.9, 1.0, 0.12)
const BOX_LINE := Color(0.4, 0.9, 1.0, 0.9)
const MARKER := Color(0.4, 1.0, 0.6)
const RANGE := Color(0.4, 0.8, 1.0, 0.35)
const TRACER := Color(0.6, 0.9, 1.0, 0.9)

var _main: Main
var _sim: Simulation
var _camera: MapCamera
var _selection: Selection
var _placement: Placement
var _enemy_renderer: EnemyRenderer
var _world: Node2D
var _overlay: Overlay
var _soldiers: Array[Soldier] = []
var _press := Vector2.ZERO
var _pressing := false
var _boxing := false
var _last_group := -1
var _last_group_msec := 0
var _markers: Array[Vector3] = []
var _tracers: Array[PackedVector2Array] = []
var _tracer_ends: Array[int] = []
var _edge_scroll := false
var _fire_while_moving := true
var _show_ranges := true
var _readout := Label.new()
var _targeting_button := Button.new()


func _ready() -> void:
	_main = MAIN_SCENE.instantiate() as Main
	add_child(_main)
	_camera = _main.get_node("Camera") as MapCamera
	_selection = _main.get_node("Selection") as Selection
	_placement = _main.get_node("Placement") as Placement
	_enemy_renderer = _main.get_node("EnemyRenderer") as EnemyRenderer
	_world = _main.get_node("World") as Node2D
	_overlay = Overlay.new()
	_overlay.proto = self
	_main.add_child(_overlay)
	# Last child of Main, so it sees unhandled input before Placement, the camera and Selection.
	var input := InputSink.new()
	input.proto = self
	_main.add_child(input)
	_build_panel()


func _process(delta: float) -> void:
	if _main.simulation != _sim:
		_hook(_main.simulation)
	_pan_by_keys(delta)
	for soldier in _soldiers:
		soldier.position = GridTransform.grid_to_world(soldier.grid_pos)
		soldier.queue_redraw()
	_overlay.queue_redraw()
	_readout.text = _state_text()
	_targeting_button.text = "Targeting: %s" % _targeting_label()


# A restart builds a new Simulation: hook it and start the soldiers again beside the base.
func _hook(sim: Simulation) -> void:
	_sim = sim
	_sim.step_observer = _on_step
	for soldier in _soldiers:
		soldier.queue_free()
	_soldiers.clear()
	var base := _sim.map.base
	var start := Vector2(base.end.x + 1.5, base.get_center().y - SOLDIER_COUNT / 4.0)
	for i in SOLDIER_COUNT:
		_spawn(start + Vector2(i % 2, i / 2) * FORMATION_SPACING)


func _spawn(grid_pos: Vector2) -> void:
	var soldier := Soldier.new()
	soldier.grid_pos = grid_pos
	soldier.target = grid_pos
	soldier.number = _soldiers.size() + 1
	_soldiers.append(soldier)
	_world.add_child(soldier)


# Soldiers act inside the sim's tick: they walk with the enemies and fire just before the dead
# are removed, so a soldier's kill lands, piles and pays the same tick as a tower's.
func _on_step(step: Simulation.Step) -> void:
	if step == Simulation.Step.MOVE_ENEMIES:
		for soldier in _soldiers:
			_walk(soldier)
	elif step == Simulation.Step.REMOVE_DEAD:
		for soldier in _soldiers:
			_fire(soldier)


func _walk(soldier: Soldier) -> void:
	if not soldier.moving:
		return
	var to_target := soldier.target - soldier.grid_pos
	var step := SOLDIER_SPEED / Simulation.TICKS_PER_SECOND
	if to_target.length() <= step:
		soldier.grid_pos = soldier.target
		soldier.moving = false
		return
	var move := to_target.normalized() * step
	# Slide along rock and buildings; stop if both axes are blocked.
	for attempt: Vector2 in [move, Vector2(move.x, 0), Vector2(0, move.y)]:
		if _walkable(soldier.grid_pos + attempt):
			soldier.grid_pos += attempt
			return
	soldier.moving = false


func _walkable(grid_pos: Vector2) -> bool:
	var cell := Vector2i(grid_pos.floor())
	if not _sim.map.in_bounds(cell) or _sim.map.is_rock(cell):
		return false
	return _sim.occupancy.building_at(cell) == Occupancy.EMPTY


func _fire(soldier: Soldier) -> void:
	soldier.cooldown -= 1
	soldier.firing = false
	if soldier.moving and not _fire_while_moving:
		return
	var enemies := _sim.enemies
	var target := enemies.target_in_range(soldier.grid_pos, SOLDIER_RANGE, soldier.targeting)
	if target == Enemies.NONE:
		return
	soldier.firing = true
	if soldier.cooldown > 0:
		return
	soldier.cooldown = Settings.interval_ticks(SOLDIER_FIRE_RATE)
	soldier.shots += 1
	var hit := enemies.positions[enemies.index_of(target)]
	enemies.damage(target, SOLDIER_DAMAGE, Enemies.NONE)
	_enemy_renderer.flash(target)
	var from := GridTransform.grid_to_world(soldier.grid_pos) + Vector2.UP * 16.0
	_tracers.append(PackedVector2Array([from, GridTransform.grid_to_world(hit)]))
	_tracer_ends.append(Time.get_ticks_msec() + TRACER_MSEC)


# --- input ---------------------------------------------------------------------------------


func handle_input(event: InputEvent) -> bool:
	if _sim == null or _placement.active:
		return false
	if event is InputEventMouseButton:
		return _mouse_button(event as InputEventMouseButton)
	if event is InputEventMouseMotion and _pressing:
		var motion := event as InputEventMouseMotion
		if motion.position.distance_to(_press) > CLICK_SLOP:
			_boxing = true
		return false
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			return _key(key)
	return false


func _mouse_button(button: InputEventMouseButton) -> bool:
	if button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_press = button.position
			_pressing = true
			_boxing = false
		elif _pressing:
			_pressing = false
			if _boxing:
				_box_select(Rect2(_press, Vector2.ZERO).expand(button.position), button.shift_pressed)
			else:
				_click(button.position, button.shift_pressed)
			_boxing = false
		return true
	if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed and _selected().size() > 0:
		_order_move(_to_world(button.position))
		return true
	return false


func _key(key: InputEventKey) -> bool:
	var command := key.ctrl_pressed or key.meta_pressed
	match key.keycode:
		KEY_SPACE:
			_sim.queue_command(Commands.SetPaused.new(not _sim.paused))
			return true
		KEY_S when not command:
			stop_selected()
			return true
		KEY_ESCAPE:
			_clear_soldiers()
			return false
		KEY_N:
			_spawn(GridTransform.world_to_grid(_to_world(get_viewport().get_mouse_position())))
			return true
		KEY_F5:
			Soldier.rings_on_top = not Soldier.rings_on_top
			return true
		KEY_F6:
			_edge_scroll = not _edge_scroll
			return true
		KEY_F7:
			_fire_while_moving = not _fire_while_moving
			return true
		KEY_F8:
			_show_ranges = not _show_ranges
			return true
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		var group := key.keycode - KEY_0
		if command:
			_save_group(group)
		else:
			_recall_group(group)
		return true
	return false


func _click(screen: Vector2, shift: bool) -> void:
	var soldier := _soldier_at(screen)
	if soldier != null:
		_selection.clear()
		if shift:
			soldier.selected = not soldier.selected
		else:
			_clear_soldiers()
			soldier.selected = true
		return
	if shift:
		return
	# Not a soldier: hand the click to the building selection (assign mode included).
	_clear_soldiers()
	var cell := GridTransform.world_to_cell(_to_world(screen))
	if _selection.is_assigning():
		_selection._assign_at(cell)
	else:
		_selection._select_at(cell)


func _box_select(box: Rect2, shift: bool) -> void:
	var boxed: Array[Soldier] = []
	for soldier in _soldiers:
		if box.has_point(_to_screen(soldier.body_world())):
			boxed.append(soldier)
	if not shift:
		_clear_soldiers()
		if boxed.size() > 0:
			_selection.clear()
		for soldier in boxed:
			soldier.selected = true
		return
	# Shift-drag adds the boxed soldiers, or takes them out when all are already selected.
	var all_selected := boxed.all(func(s: Soldier) -> bool: return s.selected)
	for soldier in boxed:
		soldier.selected = not all_selected
	if boxed.size() > 0:
		_selection.clear()


func _order_move(world: Vector2) -> void:
	var centre := GridTransform.world_to_grid(world)
	var selected := _selected()
	var columns := ceili(sqrt(selected.size()))
	var rows := ceili(float(selected.size()) / columns)
	for i in selected.size():
		var offset := Vector2(i % columns - (columns - 1) / 2.0, i / columns - (rows - 1) / 2.0)
		selected[i].target = centre + offset * FORMATION_SPACING
		selected[i].moving = true
	_markers.append(Vector3(world.x, world.y, Time.get_ticks_msec()))


func stop_selected() -> void:
	for soldier in _selected():
		soldier.moving = false
		soldier.target = soldier.grid_pos


func cycle_targeting() -> void:
	var next := Enemies.CLOSEST_TO_BASE if _targeting_label() == "Bloaters first" else Enemies.BLOATERS_FIRST
	for soldier in _selected():
		soldier.targeting = next


func _save_group(group: int) -> void:
	var bit := 1 << group
	for soldier in _soldiers:
		soldier.group_mask &= ~bit
		if soldier.selected:
			soldier.group_mask |= bit


func _recall_group(group: int) -> void:
	var members := _soldiers.filter(func(s: Soldier) -> bool: return s.group_mask & (1 << group) != 0)
	if members.is_empty():
		return
	var now := Time.get_ticks_msec()
	if group == _last_group and now - _last_group_msec <= DOUBLE_TAP_MSEC:
		var sum := Vector2.ZERO
		for member: Soldier in members:
			sum += member.grid_pos
		_camera._move_to(GridTransform.grid_to_world(sum / members.size()))
	_last_group = group
	_last_group_msec = now
	_selection.clear()
	_clear_soldiers()
	for member: Soldier in members:
		member.selected = true


func _pan_by_keys(delta: float) -> void:
	var direction := Vector2(
		float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_DOWN)) - float(Input.is_key_pressed(KEY_UP))
	)
	if _edge_scroll:
		var mouse := get_viewport().get_mouse_position()
		var size := get_viewport().get_visible_rect().size
		if mouse.x <= EDGE_MARGIN:
			direction.x -= 1
		elif mouse.x >= size.x - EDGE_MARGIN:
			direction.x += 1
		if mouse.y <= EDGE_MARGIN:
			direction.y -= 1
		elif mouse.y >= size.y - EDGE_MARGIN:
			direction.y += 1
	if direction != Vector2.ZERO:
		_camera._move_to(_camera.position + direction.normalized() * KEY_PAN_SPEED * delta / _camera.zoom)


# --- helpers --------------------------------------------------------------------------------


func _selected() -> Array[Soldier]:
	var selected: Array[Soldier] = []
	for soldier in _soldiers:
		if soldier.selected:
			selected.append(soldier)
	return selected


func _clear_soldiers() -> void:
	for soldier in _soldiers:
		soldier.selected = false


func _soldier_at(screen: Vector2) -> Soldier:
	var best: Soldier = null
	var best_distance := PICK_RADIUS
	for soldier in _soldiers:
		var distance := _to_screen(soldier.body_world()).distance_to(screen)
		if distance <= best_distance:
			best = soldier
			best_distance = distance
	return best


func _to_world(screen: Vector2) -> Vector2:
	return _overlay.get_canvas_transform().affine_inverse() * screen


func _to_screen(world: Vector2) -> Vector2:
	return _overlay.get_canvas_transform() * world


func _targeting_label() -> String:
	var modes := {}
	for soldier in _selected():
		modes[soldier.targeting] = true
	if modes.size() > 1:
		return "Mixed"
	if modes.has(Enemies.CLOSEST_TO_BASE):
		return "Closest to base"
	return "Bloaters first"


func _state_text() -> String:
	var selected := _selected()
	var lines: Array[String] = [
		"PROTOTYPE: unit control (#161)",
		"%s   speed x%d" % ["PAUSED" if _sim.paused else "running", _sim.speed],
		"Selected: %d soldier(s)%s" % [selected.size(), "  + building" if _selection.has_selection() else ""],
	]
	if selected.size() > 0:
		lines.append("Targeting: %s" % _targeting_label())
	var groups: Array[String] = []
	for group in range(1, 10):
		var count := _soldiers.filter(func(s: Soldier) -> bool: return s.group_mask & (1 << group) != 0).size()
		if count > 0:
			groups.append("%d:%d" % [group, count])
	lines.append("Groups: %s" % (", ".join(groups) if groups.size() > 0 else "none"))
	for soldier: Soldier in selected.slice(0, 8):
		var state := "Moving" if soldier.moving else ("Firing" if soldier.firing else "Idle")
		lines.append("  #%d %s, %s, %d shots" % [soldier.number, state, soldier.targeting, soldier.shots])
	lines.append_array([
		"",
		"Click / drag box: select (shift adds/removes)",
		"Right-click: Move   S: Stop   Space: pause",
		"Ctrl+1-9 save group, 1-9 select, twice: centre",
		"Pan: arrows, middle-drag, two-finger; N: add soldier",
		"F5 rings on top [%s]   F6 edge scroll [%s]" % [_on(Soldier.rings_on_top), _on(_edge_scroll)],
		"F7 fire while moving [%s]   F8 ranges [%s]" % [_on(_fire_while_moving), _on(_show_ranges)],
	])
	return "\n".join(lines)


func _on(flag: bool) -> String:
	return "on" if flag else "off"


func _build_panel() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	_readout.add_theme_font_size_override("font_size", 13)
	column.add_child(_readout)
	var row := HBoxContainer.new()
	column.add_child(row)
	var stop := Button.new()
	stop.text = "Stop (S)"
	stop.focus_mode = Control.FOCUS_NONE
	stop.pressed.connect(stop_selected)
	row.add_child(stop)
	_targeting_button.focus_mode = Control.FOCUS_NONE
	_targeting_button.pressed.connect(cycle_targeting)
	row.add_child(_targeting_button)


func draw_overlay(canvas: Node2D) -> void:
	var now := Time.get_ticks_msec()
	var line_width := 2.0 / _camera.zoom.x
	if _boxing and _pressing:
		var box := Rect2(_to_world(_press), Vector2.ZERO).expand(_to_world(get_viewport().get_mouse_position()))
		canvas.draw_rect(box, BOX_FILL)
		canvas.draw_rect(box, BOX_LINE, false, line_width)
	for soldier in _soldiers:
		if soldier.selected and _show_ranges:
			canvas.draw_polyline(GridTransform.circle(soldier.grid_pos, SOLDIER_RANGE), RANGE, 1.0)
		if soldier.selected and Soldier.rings_on_top:
			canvas.draw_polyline(GridTransform.circle(soldier.grid_pos, Soldier.RING_RADIUS), Soldier.RING, 2.0)
		if soldier.selected and soldier.moving:
			var to := GridTransform.grid_to_world(soldier.target)
			canvas.draw_dashed_line(soldier.position, to, Color(MARKER, 0.35), 1.0, 4.0)
	var live: Array[Vector3] = []
	for marker in _markers:
		var age := (now - marker.z) / MARKER_MSEC
		if age >= 1.0:
			continue
		live.append(marker)
		var centre := GridTransform.world_to_grid(Vector2(marker.x, marker.y))
		var ring := GridTransform.circle(centre, lerpf(0.9, 0.2, age), 24)
		canvas.draw_polyline(ring, Color(MARKER, 1.0 - age), 2.0)
	_markers = live
	var i := 0
	while i < _tracers.size():
		if now >= _tracer_ends[i]:
			_tracers.remove_at(i)
			_tracer_ends.remove_at(i)
			continue
		canvas.draw_polyline(_tracers[i], TRACER, 1.5)
		i += 1


class Soldier:
	extends Node2D

	const RING_RADIUS := 0.45
	const RING := Color(0.45, 1.0, 0.65)
	const BODY := Color(0.3, 0.55, 1.0)
	const BODY_EDGE := Color(0.1, 0.15, 0.35)

	static var rings_on_top := false

	var number := 0
	var grid_pos := Vector2.ZERO
	var target := Vector2.ZERO
	var moving := false
	var selected := false
	var firing := false
	var targeting := Enemies.BLOATERS_FIRST
	var cooldown := 0
	var shots := 0
	var group_mask := 0

	func body_world() -> Vector2:
		return position + Vector2.UP * 10.0

	func _draw() -> void:
		if selected and not rings_on_top:
			var ring := GridTransform.circle(grid_pos, RING_RADIUS, 32)
			for k in ring.size():
				ring[k] -= position
			draw_polyline(ring, RING, 2.0)
		var body := Rect2(-5, -20, 10, 16)
		draw_rect(body, BODY)
		draw_rect(body, BODY_EDGE, false, 1.0)
		draw_circle(Vector2(0, -24), 4.0, BODY)
		draw_circle(Vector2(0, -24), 4.0, BODY_EDGE, false, 1.0)
		draw_rect(Rect2(-6, -4, 12, 3), Color(0, 0, 0, 0.35))


class Overlay:
	extends Node2D

	var proto: Node

	func _draw() -> void:
		proto.call(&"draw_overlay", self)


class InputSink:
	extends Node

	var proto: Node

	func _unhandled_input(event: InputEvent) -> void:
		if proto.call(&"handle_input", event):
			get_viewport().set_input_as_handled()
