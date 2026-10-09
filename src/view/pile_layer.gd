class_name PileLayer
extends TileMapLayer

var _piles: Piles


func setup(simulation: Simulation) -> void:
	_piles = simulation.piles
	clear()
	simulation.pile_changed.connect(_show)


func _show(cells: Array[Vector2i]) -> void:
	for cell in cells:
		var level := _piles.level(cell)
		if level == 0:
			erase_cell(cell)
		else:
			set_cell(cell, Atlas.SOURCE_ID, Atlas.pile(level))
