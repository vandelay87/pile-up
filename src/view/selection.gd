class_name Selection
extends Node2D

## View-only selection: clicking a building or the base selects it and draws its range (a
## tower's fire range, a repair yard's repair area, a pylon's or the base's power area). The
## HUD reads its details each frame. Clicking empty ground or Esc clears it; a destroyed
## building clears itself. Placement sits later in the tree, so it sees clicks and Esc first.
## A selected repair yard can be put in assign mode (the next click on a building in its
## repair area becomes its assignment; Esc cancels) or have its assignment cleared; both queue
## commands.

const OUTLINE := Color(1.0, 1.0, 1.0, 0.9)
const RANGE := Color(1.0, 0.9, 0.4, 0.8)
const POWER_AREA := Color(0.5, 0.85, 1.0, 0.8)
const UNPOWERED := Color(0.6, 0.6, 0.6, 0.6)
const REPAIR_AREA := Color(0.35, 0.95, 0.45, 0.8)
const REPAIR_AREA_TINT := Color(0.35, 0.95, 0.45, 0.1)
const ASSIGNMENT := Color(0.35, 0.95, 0.45, 1.0)
## A left press and release further apart than this (screen pixels) is a camera drag.
const CLICK_SLOP := 6.0

var _simulation: Simulation
var _building_id := Occupancy.EMPTY
var _base := false
var _press_position := Vector2.ZERO
var _pressed := false
var _assigning := false


func setup(simulation: Simulation) -> void:
	_simulation = simulation
	clear()


func clear() -> void:
	_building_id = Occupancy.EMPTY
	_base = false
	_assigning = false
	queue_redraw()


func has_selection() -> bool:
	return _base or _building_id != Occupancy.EMPTY


## The selection's details: a title, then one line per stat. Empty when nothing is selected.
func details() -> Array[String]:
	if _simulation == null or not has_selection():
		return []
	var building := _selected_building()
	if not _base and building == null:
		return []
	return _base_stats() if _base else _building_stats(building)


func is_yard_selected() -> bool:
	var building := _selected_building()
	return building != null and building.kind == Buildings.REPAIR_YARD


func is_assigning() -> bool:
	return _assigning


func set_assigning(on: bool) -> void:
	_assigning = on and is_yard_selected()


func clear_assignment() -> void:
	if is_yard_selected():
		_simulation.queue_command(Commands.ClearAssignment.new(_building_id))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE and has_selection():
			if _assigning:
				_assigning = false
			else:
				clear()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		# Left-drag pans the camera, so a selection happens on a release close to its press.
		if button.pressed:
			_pressed = true
			_press_position = button.position
		elif _pressed:
			_pressed = false
			if button.position.distance_to(_press_position) <= CLICK_SLOP:
				var cell := GridTransform.world_to_cell(get_global_mouse_position())
				if _assigning:
					_assign_at(cell)
				else:
					_select_at(cell)


func _process(_delta: float) -> void:
	if _simulation == null or not has_selection():
		return
	var building := _selected_building()
	if not _base and building == null:
		clear()
		return
	queue_redraw()


func _select_at(cell: Vector2i) -> void:
	if _simulation == null:
		return
	clear()
	if not _simulation.map.in_bounds(cell):
		return
	if _simulation.map.is_base(cell):
		_base = true
	else:
		_building_id = _simulation.occupancy.building_at(cell)
	queue_redraw()


# The click names the building to assign; the yard stays selected and Assign switches off.
func _assign_at(cell: Vector2i) -> void:
	_assigning = false
	if not _simulation.map.in_bounds(cell):
		return
	var target := _simulation.occupancy.building_at(cell)
	if target != Occupancy.EMPTY:
		_simulation.queue_command(Commands.Assign.new(_building_id, target))


func _selected_building() -> Buildings.Building:
	if _building_id == Occupancy.EMPTY:
		return null
	return _simulation.buildings.building(_building_id)


func _building_stats(building: Buildings.Building) -> Array[String]:
	var settings := _simulation.settings
	var fire_rate: float = settings.value("towers", "fire_rate")
	var lines: Array[String] = [
		String(building.kind).capitalize(),
		_hp_line(building.hp, _simulation.buildings.max_hp(building.kind)),
		"Powered: %s" % ("yes" if building.powered else "no"),
	]
	match building.kind:
		Buildings.TOWER:
			lines.append("Damage %s" % _number(settings.tower_damage))
			lines.append("Shots/s %s" % _number(fire_rate))
			lines.append("Range %s" % _number(settings.tower_range))
			lines.append("Kills %d" % building.kills)
		Buildings.PYLON:
			lines.append("Power area %d" % _simulation.buildings.power_area(building.kind))
		Buildings.REPAIR_YARD:
			lines.append_array(_yard_stats(building))
	return lines


func _yard_stats(yard: Buildings.Building) -> Array[String]:
	var drone := _simulation.repair_yards.drone(yard.id)
	var rate: float = _simulation.settings.value("repair_yards", "repair_rate")
	var target := "auto"
	var assigned := _simulation.buildings.building(drone.assignment)
	if assigned != null:
		target = "%s #%d" % [String(assigned.kind).capitalize(), assigned.id]
	var lines: Array[String] = [
		"Repair rate %s HP/s" % _number(rate),
		"Repair area %d" % _simulation.settings.repair_area,
		"Target: %s" % target,
		"HP repaired %d" % floori(drone.repaired),
	]
	if _assigning:
		lines.append("Click a building in the repair area")
	return lines


func _base_stats() -> Array[String]:
	var lines: Array[String] = [
		"Base",
		_hp_line(_simulation.run_state.base_hp, _simulation.settings.base_hp),
		"Powered: yes",
		"Power area %d" % _simulation.settings.base_power_area,
	]
	return lines


func _hp_line(hp: float, max_hp: float) -> String:
	return "HP %d / %d" % [ceili(hp), ceili(max_hp)]


func _number(amount: float) -> String:
	return str(snappedf(amount, 0.01))


func _draw() -> void:
	if _simulation == null or not has_selection():
		return
	var grid := _simulation.power_grid
	if _base:
		_outline_cells(_simulation.map.base)
		PowerGridDrawing.outline(self, grid.base_area(), POWER_AREA, 2.0)
		return
	var building := _selected_building()
	if building == null:
		return
	_outline_cells(Rect2i(building.origin, Buildings.footprint_size(building.kind)))
	if building.kind == Buildings.TOWER:
		var colour := RANGE if building.powered else UNPOWERED
		var circle := GridTransform.circle(building.centre, _simulation.settings.tower_range)
		draw_polyline(circle, colour, 2.0)
	elif building.kind == Buildings.REPAIR_YARD:
		_draw_repair_area(building)
	else:
		var colour := POWER_AREA if building.powered else UNPOWERED
		PowerGridDrawing.outline(self, grid.area_of(building.kind, building.origin), colour, 2.0)


func _draw_repair_area(yard: Buildings.Building) -> void:
	var area := _simulation.repair_yards.repair_area(yard)
	var clipped := area.intersection(Rect2i(0, 0, _simulation.map.width, _simulation.map.height))
	var colour := REPAIR_AREA if yard.powered else UNPOWERED
	PowerGridDrawing.tint_area(self, clipped, _simulation.map, REPAIR_AREA_TINT)
	PowerGridDrawing.outline(self, clipped, colour, 2.0)
	var drone := _simulation.repair_yards.drone(yard.id)
	var assigned := _simulation.buildings.building(drone.assignment)
	if assigned != null:
		var footprint := Rect2i(assigned.origin, Buildings.footprint_size(assigned.kind))
		PowerGridDrawing.outline(self, footprint, ASSIGNMENT, 3.0)


func _outline_cells(area: Rect2i) -> void:
	PowerGridDrawing.outline(self, area, OUTLINE, 2.0)
