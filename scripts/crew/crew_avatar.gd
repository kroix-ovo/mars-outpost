extends Node3D
## Uses only snapshot positions. Selection travels to the HUD, never to the ledger.

const Figure := preload("res://scripts/crew/astronaut_figure.gd")
const CrewLooks := preload("res://scripts/crew/crew_looks.gd")

signal selected(crew_id: String)
var crew_id := ""
var _target := Vector3.ZERO
var _initialized := false
var _ring: MeshInstance3D
var _figure: Node3D
var _look_key := ""

func _ready() -> void:
	# The shared cartoon astronaut; its look is applied once the crew id is known.
	_figure = Figure.new()
	_figure.name = "Figure"
	_figure.phase = randf() * 10.0
	add_child(_figure)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.42
	_ring.mesh = torus
	_ring.position = Vector3(0, 0.04, 0)
	_ring.scale = Vector3(1.0, 0.25, 1.0)
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(1.0, 0.68, 0.22)
	_ring.material_override = ring_material
	_ring.visible = false
	add_child(_ring)

func apply_record(record: Dictionary, snap: bool = false) -> void:
	crew_id = record.id
	var point: Array = record.position_m
	_target = Vector3(point[0], point[1], point[2])
	if snap or not _initialized:
		position = _target
	_initialized = true
	$Nameplate.text = "%s · %s" % [record.display_name, record.status.capitalize()]
	var key := "%s|%s" % [record.get("definition_id", ""), record.display_name]
	if _figure != null and key != _look_key:
		_look_key = key
		_figure.apply_look(CrewLooks.look_for(str(record.get("definition_id", crew_id)), record.display_name))
	visible = record.status != "dead"

func set_selected(value: bool) -> void:
	if _ring != null:
		_ring.visible = value

func _process(dt: float) -> void:
	if _initialized:
		var heading := _target - position
		if Vector2(heading.x, heading.z).length() > 0.02:
			rotation.y = lerp_angle(rotation.y, atan2(heading.x, heading.z), 1.0 - exp(-10.0 * dt))
		if _figure != null:
			_figure.mode = "walk" if Vector2(heading.x, heading.z).length() > 0.05 else "idle"
		position = position.lerp(_target, 1.0 - exp(-12.0 * dt))

func _on_pick(_camera: Node, event: InputEvent, _at: Vector3, _normal: Vector3, _shape: int) -> void:
	if visible and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected.emit(crew_id)
