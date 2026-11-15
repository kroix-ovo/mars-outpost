extends Node3D
## Uses only snapshot positions. Selection travels to the HUD, never to the ledger.

const ACCENTS := [Color(0.93, 0.58, 0.16), Color(0.30, 0.76, 0.92), Color(0.88, 0.34, 0.26),
	Color(0.55, 0.80, 0.38), Color(0.78, 0.55, 0.90), Color(0.95, 0.85, 0.35)]

signal selected(crew_id: String)
var crew_id := ""
var _target := Vector3.ZERO
var _initialized := false
var _ring: MeshInstance3D
var _accent: StandardMaterial3D

func _ready() -> void:
	# Helmet, visor, life-support pack and an accent stripe built from primitives.
	_accent = _material(ACCENTS[0], 0.6)
	_part(_sphere(0.17), Vector3(0, 1.2, 0), _material(Color(0.86, 0.85, 0.82), 0.5))
	var visor := _material(Color(0.12, 0.13, 0.16), 0.15)
	visor.metallic = 0.6
	_part(_sphere(0.12), Vector3(0, 1.21, 0.08), visor).scale = Vector3(1.05, 0.8, 0.7)
	_part(_box(Vector3(0.3, 0.42, 0.16)), Vector3(0, 0.78, -0.2), _material(Color(0.62, 0.6, 0.57), 0.8))
	_part(_box(Vector3(0.42, 0.06, 0.3)), Vector3(0, 0.92, 0), _accent)
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
	if _accent != null:
		_accent.albedo_color = ACCENTS[posmod(crew_id.hash(), ACCENTS.size())]
	visible = record.status != "dead"

func set_selected(value: bool) -> void:
	if _ring != null:
		_ring.visible = value

func _process(dt: float) -> void:
	if _initialized:
		var heading := _target - position
		if Vector2(heading.x, heading.z).length() > 0.02:
			rotation.y = lerp_angle(rotation.y, atan2(heading.x, heading.z), 1.0 - exp(-10.0 * dt))
		position = position.lerp(_target, 1.0 - exp(-12.0 * dt))

func _on_pick(_camera: Node, event: InputEvent, _at: Vector3, _normal: Vector3, _shape: int) -> void:
	if visible and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		selected.emit(crew_id)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh

func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _part(mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material
	add_child(node)
	return node
