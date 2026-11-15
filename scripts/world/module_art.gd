class_name ModuleArt
extends Node3D
## Lightweight procedural module models shared by the authored building scenes and by
## definitions without a scene (the synthetic training fixtures). Presentation only: no
## collision, no simulation reads, no state writes.
##
## The model is authored in a "front space" where +Z faces the module's first entrance cell and
## the anchor cell centre is the origin, matching BuildingNode's authored-art convention. The
## owning BuildingNode applies placement rotation afterwards.
##
## Palette: charcoal/graphite structure, off-white shells, amber hazard accents and cyan
## indicators. Emissive materials carry the "indicator" meta so BuildingNode can dim them when a
## module is off, damaged or unfinished.

const CHARCOAL := Color(0.15, 0.15, 0.16)
const GRAPHITE := Color(0.27, 0.27, 0.28)
const SHELL := Color(0.70, 0.68, 0.64)
const SHELL_WARM := Color(0.66, 0.60, 0.52)
const AMBER := Color(0.90, 0.55, 0.16)
const CYAN := Color(0.30, 0.78, 0.92)
const PV := Color(0.09, 0.13, 0.23)
const GLASS := Color(0.48, 0.56, 0.60, 0.42)

@export var kind: String = ""
## Definition-local footprint cells. Filled from the owning BuildingNode's definition when empty.
var footprint: Array = []
var entrances: Array = []

## Approximate model top in metres, used to place status lights and name labels.
var top_height := 1.2
var _w := 1.0  # extent across the front (local X)
var _d := 1.0  # extent front-to-back (local Z)
var _model: Node3D


static func kind_for(definition: Dictionary) -> String:
	var key := (str(definition.get("scene_path", "")) + " " + str(definition.get("id", ""))).to_lower()
	for pair in [["solar", "solar"], ["generator", "solar"], ["battery", "battery"],
			["scrubber", "scrubber"], ["electrolyzer", "electrolyzer"], ["recycler", "recycler"],
			["greenhouse", "greenhouse"], ["storage", "storage"]]:
		if key.contains(pair[0]):
			return pair[1]
	return "generic"


func _ready() -> void:
	if _model == null:
		build()


func build() -> void:
	if _model != null:
		_model.queue_free()
	var owner_node := get_parent()
	if footprint.is_empty() and owner_node != null and "definition" in owner_node:
		footprint = owner_node.definition.get("footprint_cells", [])
		entrances = owner_node.definition.get("entrance_cells", [])
	if footprint.is_empty():
		footprint = [[0, 0]]
	if kind.is_empty() and owner_node != null and "definition" in owner_node:
		kind = kind_for(owner_node.definition)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for cell in footprint:
		lo = Vector2(minf(lo.x, cell[0]), minf(lo.y, cell[1]))
		hi = Vector2(maxf(hi.x, cell[0]), maxf(hi.y, cell[1]))
	var centre := Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.y + hi.y) * 0.5)
	var size_x := hi.x - lo.x + 1.0
	var size_z := hi.y - lo.y + 1.0
	# Face the first entrance. Entrances are axis-aligned neighbours of the footprint.
	var yaw := 0.0
	if not entrances.is_empty():
		var e: Array = entrances[0]
		var dx: float = float(e[0]) - centre.x
		var dz: float = float(e[1]) - centre.z
		if absf(dx) > absf(dz):
			yaw = PI * 0.5 if dx > 0.0 else -PI * 0.5
		else:
			yaw = 0.0 if dz >= 0.0 else PI
	var sideways := absf(sin(yaw)) > 0.5
	_w = size_z if sideways else size_x
	_d = size_x if sideways else size_z
	_model = Node3D.new()
	_model.name = "Model"
	_model.position = centre
	_model.rotation.y = yaw
	add_child(_model)
	top_height = float({"solar": 0.95, "battery": 1.2, "scrubber": 1.42, "electrolyzer": 1.45,
		"recycler": 1.5, "storage": 1.15, "greenhouse": 1.2}.get(kind, 1.0))
	match kind:
		"solar": _solar()
		"battery": _battery()
		"scrubber": _scrubber()
		"electrolyzer": _electrolyzer()
		"recycler": _recycler()
		"storage": _storage()
		"greenhouse": _greenhouse()
		_: _generic()


# ---------------------------------------------------------------- models

func _pad(inset: float = 0.1) -> void:
	_box(Vector3(_w - inset, 0.06, _d - inset), Vector3(0, 0.03, 0), mat(CHARCOAL, 0.95))
	# Amber corner markers keep footprints legible without a dominant grid.
	var amber := mat(AMBER, 0.6)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(0.12, 0.065, 0.03), Vector3(sx * (_w - inset - 0.12) * 0.5, 0.035, sz * (_d - inset - 0.03) * 0.5), amber)


func _solar() -> void:
	var frame := mat(GRAPHITE, 0.6, 0.4)
	var cell_mat := mat(PV, 0.22, 0.55)
	var line_mat := mat(Color(0.32, 0.38, 0.48), 0.4, 0.3)
	var count := maxi(1, int(round(_w)))
	var start := -(_w - 1.0) * 0.5
	for i in count:
		var x := start + i
		_cyl(0.035, 0.05, 0.62, Vector3(x, 0.31, -0.05), frame)
		_cyl(0.11, 0.12, 0.05, Vector3(x, 0.025, -0.05), mat(CHARCOAL, 0.9))
		var tilt := Node3D.new()
		tilt.position = Vector3(x, 0.66, -0.05)
		tilt.rotation_degrees = Vector3(-24, 0, 0)
		_model.add_child(tilt)
		_box(Vector3(0.96, 0.04, 0.82), Vector3.ZERO, frame, Vector3.ZERO, tilt)
		_box(Vector3(0.9, 0.02, 0.76), Vector3(0, 0.025, 0), cell_mat, Vector3.ZERO, tilt)
		for k in [-1, 0, 1]:
			_box(Vector3(0.012, 0.024, 0.76), Vector3(k * 0.3, 0.03, 0), line_mat, Vector3.ZERO, tilt)
		_box(Vector3(0.9, 0.024, 0.012), Vector3(0, 0.03, 0), line_mat, Vector3.ZERO, tilt)
	# Torque tube spanning the row and a small inverter cabinet facing the access side.
	_cyl(0.035, 0.035, _w - 0.1, Vector3(0, 0.6, -0.05), frame, Vector3(0, 0, 90))
	var cab := Vector3(0, 0.0, 0.36)
	_box(Vector3(0.3, 0.34, 0.16), cab + Vector3(0, 0.2, 0), mat(SHELL, 0.7))
	_box(Vector3(0.31, 0.05, 0.17), cab + Vector3(0, 0.3, 0), mat(AMBER, 0.6))
	_box(Vector3(0.08, 0.03, 0.01), cab + Vector3(0, 0.16, 0.085), indicator(CYAN))


func _battery() -> void:
	_pad()
	var body := mat(CHARCOAL, 0.75, 0.25)
	_box(Vector3(0.8, 0.98, 0.62), Vector3(0, 0.55, -0.02), body)
	for k in [-1, 0, 1]:
		_box(Vector3(0.22, 0.78, 0.03), Vector3(k * 0.25, 0.53, 0.3), mat(SHELL, 0.65))
		_box(Vector3(0.14, 0.025, 0.01), Vector3(k * 0.25, 0.86, 0.318), indicator(CYAN))
	_box(Vector3(0.82, 0.06, 0.64), Vector3(0, 0.15, -0.02), mat(AMBER, 0.6))
	for k in 6:
		_box(Vector3(0.025, 0.1, 0.5), Vector3(-0.3 + k * 0.12, 1.09, -0.02), mat(GRAPHITE, 0.6, 0.4))
	_cyl(0.035, 0.035, 0.18, Vector3(-0.32, 1.1, 0.22), mat(AMBER, 0.5))
	_cyl(0.035, 0.035, 0.18, Vector3(0.32, 1.1, 0.22), mat(GRAPHITE, 0.5))


func _scrubber() -> void:
	_pad()
	var shell := mat(SHELL, 0.7, 0.1)
	_box(Vector3(0.78, 1.18, 0.66), Vector3(0, 0.65, -0.02), shell)
	_box(Vector3(0.8, 0.08, 0.68), Vector3(0, 1.22, -0.02), mat(GRAPHITE, 0.6, 0.3))
	var slat := mat(CHARCOAL, 0.8)
	for k in 7:
		_box(Vector3(0.62, 0.03, 0.07), Vector3(0, 0.36 + k * 0.1, 0.32), slat, Vector3(32, 0, 0))
	_cyl(0.27, 0.29, 0.14, Vector3(0, 1.33, -0.02), mat(CHARCOAL, 0.7))
	_cyl(0.06, 0.06, 0.16, Vector3(0, 1.36, -0.02), mat(GRAPHITE, 0.5, 0.5))
	for k in 3:
		_box(Vector3(0.48, 0.015, 0.06), Vector3(0, 1.41, -0.02), mat(GRAPHITE, 0.5, 0.4), Vector3(0, k * 60.0, 0))
	_cyl(0.09, 0.09, 0.7, Vector3(0.42, 0.62, -0.18), mat(GRAPHITE, 0.6, 0.4))
	_box(Vector3(0.12, 0.03, 0.01), Vector3(0.22, 1.08, 0.315), indicator(CYAN))
	_box(Vector3(0.79, 0.05, 0.67), Vector3(0, 0.2, -0.02), mat(AMBER, 0.6))


func _electrolyzer() -> void:
	_pad()
	var shell := mat(SHELL, 0.65, 0.1)
	_box(Vector3(0.42, 1.25, 0.5), Vector3(-0.17, 0.68, -0.04), shell)
	for k in 5:
		_box(Vector3(0.44, 0.03, 0.52), Vector3(-0.17, 0.3 + k * 0.2, -0.04), mat(GRAPHITE, 0.6, 0.3))
	# Oxygen (cyan band) and hydrogen (amber band) product bottles.
	_cyl(0.13, 0.13, 0.95, Vector3(0.22, 0.56, -0.16), mat(SHELL_WARM, 0.5, 0.2))
	_sphere(0.13, Vector3(0.22, 1.03, -0.16), mat(SHELL_WARM, 0.5, 0.2))
	_cyl(0.135, 0.135, 0.06, Vector3(0.22, 0.8, -0.16), mat(CYAN, 0.5))
	_cyl(0.1, 0.1, 0.8, Vector3(0.24, 0.48, 0.18), mat(GRAPHITE, 0.5, 0.3))
	_sphere(0.1, Vector3(0.24, 0.88, 0.18), mat(GRAPHITE, 0.5, 0.3))
	_cyl(0.105, 0.105, 0.06, Vector3(0.24, 0.7, 0.18), mat(AMBER, 0.5))
	var pipe := mat(GRAPHITE, 0.5, 0.5)
	_cyl(0.025, 0.025, 0.32, Vector3(0.03, 1.12, -0.16), pipe, Vector3(0, 0, 90))
	_cyl(0.025, 0.025, 0.3, Vector3(0.03, 0.95, 0.18), pipe, Vector3(0, 0, 90))
	_cyl(0.04, 0.04, 0.25, Vector3(-0.17, 1.4, -0.04), mat(CHARCOAL, 0.7))
	_box(Vector3(0.12, 0.03, 0.01), Vector3(-0.17, 1.12, 0.215), indicator(CYAN))


func _recycler() -> void:
	_pad()
	var shell := mat(SHELL, 0.6, 0.15)
	var length := maxf(0.9, _w - 0.5)
	var axis := Vector3(0, 0, 90)
	_cyl(0.36, 0.36, length, Vector3(-0.1, 0.62, -0.08), shell, axis)
	for sx in [-1.0, 1.0]:
		_sphere(0.36, Vector3(-0.1 + sx * length * 0.5, 0.62, -0.08), shell, Vector3(1.0, 1.0, 1.0) * Vector3(0.45, 1.0, 1.0))
		_box(Vector3(0.12, 0.3, 0.6), Vector3(-0.1 + sx * length * 0.32, 0.2, -0.08), mat(CHARCOAL, 0.8))
	for k in [-1, 0, 1]:
		_cyl(0.375, 0.375, 0.05, Vector3(-0.1 + k * length * 0.25, 0.62, -0.08), mat(GRAPHITE, 0.6, 0.3), axis)
	var col := Vector3(_w * 0.5 - 0.25, 0, 0.22)
	_cyl(0.15, 0.15, 1.3, col + Vector3(0, 0.71, 0), mat(GRAPHITE, 0.55, 0.35))
	_cyl(0.16, 0.16, 0.06, col + Vector3(0, 1.0, 0), mat(CYAN, 0.4))
	_cyl(0.03, 0.03, 0.5, col + Vector3(-0.25, 1.02, 0), mat(GRAPHITE, 0.5, 0.5), axis)
	_box(Vector3(0.18, 0.04, 0.01), Vector3(-0.1, 0.62, 0.285), indicator(CYAN))
	_box(Vector3(length * 0.5, 0.05, 0.02), Vector3(-0.1, 0.36, 0.25), mat(AMBER, 0.6))


func _storage() -> void:
	# Habitat-like pressurized module on cradles with a front hatch and window band.
	_pad(0.14)
	var shell := mat(SHELL, 0.6, 0.12)
	var length := maxf(0.8, _w - 0.45)
	var radius := minf(0.42, _d * 0.42)
	var axis := Vector3(0, 0, 90)
	var y := 0.2 + radius
	_cyl(radius, radius, length, Vector3(0, y, 0), shell, axis)
	for sx in [-1.0, 1.0]:
		_sphere(radius, Vector3(sx * length * 0.5, y, 0), shell, Vector3(0.5, 1.0, 1.0))
		_box(Vector3(0.1, 0.24, radius * 1.7), Vector3(sx * length * 0.33, 0.14, 0), mat(CHARCOAL, 0.8))
	for k in [-1, 0, 1]:
		_cyl(radius + 0.015, radius + 0.015, 0.05, Vector3(k * length * 0.3, y, 0), mat(GRAPHITE, 0.6, 0.3), axis)
	_box(Vector3(length * 0.7, 0.05, 0.02), Vector3(0, y + radius * 0.45, radius * 0.88), indicator(Color(0.45, 0.68, 0.78), 0.6))
	_box(Vector3(0.34, 0.42, 0.08), Vector3(0, y - 0.04, radius + 0.01), mat(CHARCOAL, 0.7))
	_box(Vector3(0.4, 0.05, 0.09), Vector3(0, y + 0.2, radius + 0.01), mat(AMBER, 0.6))
	_box(Vector3(length * 0.55, 0.03, 0.5), Vector3(0, y + radius + 0.04, -0.05), mat(GRAPHITE, 0.4, 0.5))


func _greenhouse() -> void:
	# Unplanted shell: glazing and ribs only, no crops implied.
	_box(Vector3(_w - 0.1, 0.18, _d - 0.1), Vector3(0, 0.09, 0), mat(GRAPHITE, 0.85))
	var dome := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.is_hemisphere = true
	mesh.radial_segments = 24
	mesh.rings = 8
	dome.mesh = mesh
	dome.scale = Vector3(_w - 0.2, 2.0, _d - 0.2)
	dome.position = Vector3(0, 0.18, 0)
	var glass := mat(GLASS, 0.15, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dome.material_override = glass
	_model.add_child(dome)
	var rib := mat(CHARCOAL, 0.6, 0.3)
	for k in 5:
		var z := -(_d - 0.4) * 0.5 + k * (_d - 0.4) / 4.0
		var t := 1.0 - pow(2.0 * z / (_d - 0.2), 2.0)
		var torus := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.47
		ring.outer_radius = 0.5
		torus.mesh = ring
		torus.rotation_degrees = Vector3(90, 0, 0)
		torus.scale = Vector3((_w - 0.2) * sqrt(maxf(t, 0.05)), 1.0, 2.0 * sqrt(maxf(t, 0.05)))
		torus.position = Vector3(0, 0.18, z)
		torus.material_override = rib
		_model.add_child(torus)
	_box(Vector3(0.5, 0.7, 0.2), Vector3(0, 0.35, _d * 0.5 - 0.05), mat(SHELL, 0.6))
	_box(Vector3(0.52, 0.05, 0.21), Vector3(0, 0.68, _d * 0.5 - 0.05), mat(AMBER, 0.6))


func _generic() -> void:
	_pad()
	_box(Vector3(_w - 0.25, 0.9, _d - 0.25), Vector3(0, 0.5, 0), mat(SHELL, 0.7))
	_box(Vector3(_w - 0.24, 0.06, _d - 0.24), Vector3(0, 0.2, 0), mat(AMBER, 0.6))


# ---------------------------------------------------------------- helpers

static func mat(color: Color, roughness: float = 0.7, metallic: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


static func indicator(color: Color, energy: float = 1.4) -> StandardMaterial3D:
	var m := mat(color.darkened(0.3), 0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.set_meta("indicator", energy)
	return m


func _box(size: Vector3, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(mesh, pos, material, rot, parent)


func _cyl(top: float, bottom: float, height: float, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 20
	mesh.rings = 1
	return _add(mesh, pos, material, rot, null)


func _sphere(radius: float, pos: Vector3, material: Material, scale_by: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	var node := _add(mesh, pos, material, Vector3.ZERO, null)
	node.scale = scale_by
	return node


func _add(mesh: Mesh, pos: Vector3, material: Material, rot: Vector3, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.rotation_degrees = rot
	node.material_override = material
	(parent if parent != null else _model).add_child(node)
	return node
