extends Node3D
## Uses only snapshot positions. Selection travels to the HUD, never to the ledger.

signal selected(crew_id: String)
var crew_id := ""
var _target := Vector3.ZERO
var _initialized := false

func apply_record(record: Dictionary, snap: bool = false) -> void:
	crew_id = record.id
	var point: Array = record.position_m
	_target = Vector3(point[0], point[1], point[2])
	if snap or not _initialized:
		position = _target
	_initialized = true
	$Nameplate.text = "%s · %s" % [record.display_name, record.status.capitalize()]
	visible = record.status != "dead"
	$Picker.input_ray_pickable = visible

func set_selected(active: bool) -> void:
	$Nameplate.modulate = Color("#ffe3a8") if active else Color.WHITE

func _process(dt: float) -> void:
	if _initialized:
		position = position.lerp(_target, 1.0 - exp(-12.0 * dt))

func _on_pick(_camera: Node, event: InputEvent, _at: Vector3, _normal: Vector3, _shape: int) -> void:
	if visible and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected.emit(crew_id)
