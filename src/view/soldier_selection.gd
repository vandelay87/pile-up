class_name SoldierSelection
extends Node2D

## View-only soldier selection, StarCraft-style, and the router for every left click on the
## world. A click on a soldier selects it alone; a left-drag box selects every soldier inside
## it, never buildings; shift adds or removes. A click on a building or the base goes to the
## building [Selection] and clears the soldiers; a click on empty ground or Esc clears both.
## Ctrl+1–9 saves the selected soldiers as a group, 1–9 selects it again, and the same number
## twice in quick succession centres the camera on it. The selection and groups drop soldiers
## that die. Placement sits later in the tree, so it sees clicks and Esc first, and no box
## starts while a building is placed. The selection marker is drawn above everything.

const CLUSTER := &"cluster"
const LINE := &"line"
const FORMATION_NAMES := {CLUSTER: "Cluster", LINE: "Line"}
const TARGETING_NAMES := {
	Enemies.BLOATERS_FIRST: "Bloaters first",
	Enemies.CLOSEST_TO_BASE: "Closest to base",
}
## Shown for the targeting when the selected soldiers' modes differ.
const MIXED := "Mixed"
## A left press and release further apart than this (screen pixels) is a box.
const CLICK_SLOP := 6.0
## How far outside a soldier's figure (world pixels) a click still picks it.
const PICK_SLACK := 3.0
const DOUBLE_PRESS_SECONDS := 0.35
const MARKER := Color(0.4, 1.0, 0.5, 0.95)
const MARKER_RADIUS := 9.0
const BOX_EDGE := Color(0.4, 1.0, 0.5, 0.9)
const BOX_FILL := Color(0.4, 1.0, 0.5, 0.1)

## The army-wide formation the next Move order takes (#190), flipped from the command card.
var formation := CLUSTER

var _simulation: Simulation
var _buildings: Selection
var _camera: MapCamera
## The selected soldiers' ids, in selection order.
var _ids := PackedInt32Array()
var _groups: Dictionary[int, PackedInt32Array] = {}
var _last_group := 0
var _last_group_msec := 0
var _pressed := false
var _boxing := false
var _press_screen := Vector2.ZERO
var _press_world := Vector2.ZERO


func setup(simulation: Simulation, buildings: Selection, camera: MapCamera) -> void:
	_simulation = simulation
	_buildings = buildings
	_camera = camera
	_groups.clear()
	formation = CLUSTER
	clear()


func _ready() -> void:
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX


func clear() -> void:
	_ids = PackedInt32Array()
	_cancel_box()


func has_selection() -> bool:
	return not _ids.is_empty()


## The selected soldiers' ids, in selection order.
func selected() -> PackedInt32Array:
	return _ids


## Selects [param id] alone, or with shift takes it out, as a click on its tile does.
func pick(id: int, shift: bool) -> void:
	if shift:
		_ids = _without(_ids, PackedInt32Array([id]))
	else:
		_ids = PackedInt32Array([id])


## The selected soldiers' targeting, or [constant MIXED] when they differ.
func targeting_name() -> String:
	var mode := _shared_targeting()
	return MIXED if mode.is_empty() else TARGETING_NAMES[mode]


## Flips the selected soldiers' targeting; from Mixed it sets Bloaters first.
func flip_targeting() -> void:
	if not has_selection():
		return
	var mode := Enemies.BLOATERS_FIRST
	if _shared_targeting() == Enemies.BLOATERS_FIRST:
		mode = Enemies.CLOSEST_TO_BASE
	_simulation.queue_command(Commands.SetSoldierTargeting.new(_ids, mode))


func flip_formation() -> void:
	formation = LINE if formation == CLUSTER else CLUSTER


## The details of one soldier, or of several: a title, then one line per stat.
func details() -> Array[String]:
	if not has_selection():
		return []
	if _ids.size() > 1:
		var kills := 0
		for id in _ids:
			kills += _simulation.soldiers.kills[_simulation.soldiers.index_of(id)]
		var lines: Array[String] = ["%d soldiers" % _ids.size(), "Kills %d" % kills]
		return lines
	var soldiers := _simulation.soldiers
	var settings := _simulation.settings
	var i := soldiers.index_of(_ids[0])
	var reach: float = settings.value("soldiers", "range")
	var high_ground: float = soldiers.elevation(i) * settings.value("soldiers", "range_per_level")
	var range_line := "Range %s" % _number(reach + high_ground)
	if high_ground > 0.0:
		range_line += " (+%s high ground)" % _number(high_ground)
	var damage: float = settings.value("soldiers", "damage")
	var fire_rate: float = settings.value("soldiers", "fire_rate")
	var one: Array[String] = [
		"Soldier",
		"HP %d / %d" % [ceili(soldiers.hp[i]), ceili(settings.soldier_hp)],
		_status(i),
		"Damage %s" % _number(damage),
		"Shots/s %s" % _number(fire_rate),
		range_line,
		"Kills %d" % soldiers.kills[i],
	]
	return one


## The selected soldier's HP as a fraction of its max, by index into [method selected].
func hp_fraction(slot: int) -> float:
	var i := _simulation.soldiers.index_of(_ids[slot])
	return _simulation.soldiers.hp[i] / _simulation.settings.soldier_hp


func _unhandled_input(event: InputEvent) -> void:
	if _simulation == null:
		return
	if event is InputEventKey:
		_key(event as InputEventKey)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_pressed = true
			_boxing = false
			_press_screen = button.position
			_press_world = get_global_mouse_position()
		elif _pressed:
			_release(button.shift_pressed)
	elif event is InputEventMouseMotion and _pressed and not _boxing:
		var motion := event as InputEventMouseMotion
		_boxing = motion.position.distance_to(_press_screen) > CLICK_SLOP


func _key(key: InputEventKey) -> void:
	if not key.pressed or key.echo:
		return
	var handled := true
	if key.keycode == KEY_ESCAPE and has_selection() and not _buildings.has_selection():
		clear()
	elif key.keycode >= KEY_1 and key.keycode <= KEY_9:
		var group := key.keycode - KEY_0
		if key.ctrl_pressed or key.meta_pressed:
			if has_selection():
				_groups[group] = _ids
		else:
			_recall(group)
	elif key.keycode == KEY_A and has_selection():
		flip_targeting()
	elif key.keycode == KEY_F and has_selection():
		flip_formation()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _simulation == null:
		return
	_drop_dead()
	# A release over the HUD never reaches the world, so a box ends when the button is up.
	if _pressed and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_release(Input.is_key_pressed(KEY_SHIFT))
	queue_redraw()


func _release(shift: bool) -> void:
	_pressed = false
	if _boxing:
		_boxing = false
		_select_box(Rect2(_press_world, Vector2.ZERO).expand(get_global_mouse_position()), shift)
		return
	var point := get_global_mouse_position()
	var id := _soldier_at(point)
	if id != Soldiers.NONE:
		_buildings.clear()
		if shift and id in _ids:
			_ids = _without(_ids, PackedInt32Array([id]))
		elif shift:
			_ids.append(id)
		else:
			_ids = PackedInt32Array([id])
		return
	if shift and has_selection():
		return
	clear()
	_buildings.click(GridTransform.world_to_cell(point))


# Shift adds the boxed soldiers, or takes them out when every one is already selected.
func _select_box(box: Rect2, shift: bool) -> void:
	var boxed := PackedInt32Array()
	var soldiers := _simulation.soldiers
	for i in soldiers.count:
		if box.has_point(_body_centre(i)):
			boxed.append(soldiers.ids[i])
	if not shift:
		_buildings.clear()
		_ids = boxed
		return
	if boxed.is_empty():
		return
	_buildings.clear()
	var all_selected := true
	for id in boxed:
		all_selected = all_selected and id in _ids
	if all_selected:
		_ids = _without(_ids, boxed)
		return
	for id in boxed:
		if id not in _ids:
			_ids.append(id)


func _recall(group: int) -> void:
	var ids: PackedInt32Array = _groups.get(group, PackedInt32Array())
	if ids.is_empty():
		return
	var now := Time.get_ticks_msec()
	var double := group == _last_group and now - _last_group_msec <= DOUBLE_PRESS_SECONDS * 1000
	_last_group = group
	_last_group_msec = now
	_buildings.clear()
	_ids = ids.duplicate()
	if double:
		var sum := Vector2.ZERO
		for id in ids:
			sum += _simulation.soldiers.positions[_simulation.soldiers.index_of(id)]
		_camera.centre_on(GridTransform.grid_to_world(sum / ids.size()))


func _drop_dead() -> void:
	_ids = _living(_ids)
	for group in _groups:
		_groups[group] = _living(_groups[group])


func _living(ids: PackedInt32Array) -> PackedInt32Array:
	var living := PackedInt32Array()
	for id in ids:
		if _simulation.soldiers.index_of(id) != Soldiers.NONE:
			living.append(id)
	return living


func _without(ids: PackedInt32Array, removed: PackedInt32Array) -> PackedInt32Array:
	var kept := PackedInt32Array()
	for id in ids:
		if id not in removed:
			kept.append(id)
	return kept


# The frontmost soldier whose figure is under [param point], or NONE.
func _soldier_at(point: Vector2) -> int:
	var soldiers := _simulation.soldiers
	var found := Soldiers.NONE
	var front := -INF
	var region := Vector2(Atlas.SOLDIER_REGION.size)
	for i in soldiers.count:
		var foot := _foot(i)
		var figure := Rect2(foot - Vector2(region.x / 2.0, region.y), region).grow(PICK_SLACK)
		if figure.has_point(point) and foot.y > front:
			front = foot.y
			found = soldiers.ids[i]
	return found


# Where the soldier's figure stands on screen, lifted by its cell's pile level.
func _foot(index: int) -> Vector2:
	var lift := float(_simulation.soldiers.elevation(index) * Atlas.PILE_SLAB_HEIGHT)
	return GridTransform.grid_to_world(_simulation.soldiers.positions[index]) - Vector2(0, lift)


func _body_centre(index: int) -> Vector2:
	return _foot(index) - Vector2(0, Atlas.SOLDIER_REGION.size.y / 2.0)


# The targeting every selected soldier shares, or empty when they differ.
func _shared_targeting() -> StringName:
	var soldiers := _simulation.soldiers
	var shared := StringName()
	for id in _ids:
		var mode := soldiers.targeting(soldiers.index_of(id))
		if shared.is_empty():
			shared = mode
		elif mode != shared:
			return StringName()
	return shared


# Moving while under an order, else Firing with a target, else Idle.
func _status(index: int) -> String:
	if _simulation.soldiers.orders[index] != Soldiers.NONE:
		return "Moving"
	if _simulation.soldiers.targets[index] != Enemies.NONE:
		return "Firing"
	return "Idle"


func _number(amount: float) -> String:
	return str(snappedf(amount, 0.01))


func _cancel_box() -> void:
	_pressed = false
	_boxing = false


func _draw() -> void:
	if _simulation == null:
		return
	var width := 2.0 / _camera.zoom.x
	for id in _ids:
		var foot := _foot(_simulation.soldiers.index_of(id))
		draw_set_transform(foot, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, MARKER_RADIUS, 0.0, TAU, 24, MARKER, width * 2.0)
	draw_set_transform(Vector2.ZERO)
	if _boxing:
		var box := Rect2(_press_world, Vector2.ZERO).expand(get_global_mouse_position())
		draw_rect(box, BOX_FILL)
		draw_rect(box, BOX_EDGE, false, width)
