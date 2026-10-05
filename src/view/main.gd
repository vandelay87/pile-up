extends Node

var _simulation := Simulation.new()


func _physics_process(_delta: float) -> void:
	_simulation.tick()
