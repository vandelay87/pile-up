extends Node

var _simulation: Simulation


func _ready() -> void:
	var loaded := Settings.load_file(Settings.DEFAULTS_PATH)
	if loaded.settings == null:
		push_error(loaded.error)
		OS.alert(loaded.error, "pile-up: invalid settings")
		get_tree().quit(1)
		return
	_simulation = Simulation.new(loaded.settings)


func _physics_process(_delta: float) -> void:
	if _simulation != null:
		_simulation.tick()
