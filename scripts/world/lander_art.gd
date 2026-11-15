extends Node3D
## Pre-landed habitat/lander model. Presentation only: no collision and no simulation reads.
## The airlock faces +X, toward the base airlock cell that main_world places it beside.

const Art := preload("res://scripts/world/module_art.gd")


func _ready() -> void:
	var shell := Art.mat(Art.SHELL, 0.62, 0.12)
	var warm := Art.mat(Art.SHELL_WARM, 0.7, 0.1)
	var dark := Art.mat(Art.CHARCOAL, 0.8, 0.2)
	var metal := Art.mat(Art.GRAPHITE, 0.45, 0.6)
	var amber := Art.mat(Art.AMBER, 0.6)
	# Pressure hull: lower drum, tapered upper section and a flat docking crown.
	_cyl(1.25, 1.3, 1.9, Vector3(0, 1.85, 0), shell)
	_cyl(0.85, 1.25, 1.1, Vector3(0, 3.35, 0), warm)
	_cyl(0.55, 0.85, 0.35, Vector3(0, 4.07, 0), shell)
	_cyl(0.5, 0.5, 0.12, Vector3(0, 4.3, 0), dark)
	for y in [1.05, 2.78]:
		_cyl(1.32, 1.32, 0.12, Vector3(0, y, 0), metal)
	_cyl(1.31, 1.31, 0.08, Vector3(0, 2.2, 0), amber)
	# Descent stage, engine bell and service bay panels.
	_cyl(1.05, 1.15, 0.3, Vector3(0, 0.85, 0), dark)
	_cyl(0.32, 0.55, 0.5, Vector3(0, 0.45, 0), metal)
	for k in 6:
		var angle := k * TAU / 6.0 + 0.3
		var panel := _box(Vector3(0.5, 0.75, 0.04), Vector3(cos(angle) * 1.27, 1.6, sin(angle) * 1.27), warm)
		panel.rotation.y = -angle + PI * 0.5
	# Four splayed landing legs with footpads.
	for k in 4:
		var angle := PI * 0.25 + k * PI * 0.5
		var out := Vector3(cos(angle), 0, sin(angle))
		# Footpads stay within the old lander's ~1.75 m radius so its footprint does not grow.
		var leg := _cyl(0.07, 0.08, 1.4, out * 1.42 + Vector3(0, 0.62, 0), metal)
		leg.look_at_from_position(leg.position, out * 1.62 + Vector3(0, 0.05, 0), Vector3.UP)
		leg.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		_cyl(0.22, 0.26, 0.08, out * 1.62 + Vector3(0, 0.04, 0), dark)
	# Airlock vestibule, hatch and steps down to the apron.
	_box(Vector3(0.75, 1.35, 0.95), Vector3(1.45, 1.55, 0), shell)
	_box(Vector3(0.06, 1.0, 0.62), Vector3(1.84, 1.5, 0), dark)
	_box(Vector3(0.07, 0.08, 0.7), Vector3(1.85, 2.03, 0), amber)
	_box(Vector3(0.05, 0.05, 0.18), Vector3(1.86, 1.45, 0.22), Art.indicator(Art.CYAN))
	for k in 4:
		_box(Vector3(0.28, 0.06, 0.6), Vector3(2.0 + k * 0.22, 0.86 - k * 0.24, 0), metal)
	# Windows, radiator wing and comms mast.
	for k in 3:
		var angle := -0.9 + k * 0.6
		var window := _box(Vector3(0.05, 0.22, 0.36), Vector3(cos(angle) * 1.27, 2.5, sin(angle) * 1.27), Art.indicator(Color(0.55, 0.72, 0.82), 0.5))
		window.rotation.y = -angle
	_box(Vector3(0.05, 1.1, 1.6), Vector3(-1.5, 2.6, 0.0), metal)
	_cyl(0.03, 0.03, 0.9, Vector3(0.25, 4.75, 0.2), metal)
	var dish := _cyl(0.22, 0.04, 0.08, Vector3(0.25, 5.2, 0.2), Art.mat(Art.GRAPHITE, 0.5, 0.4))
	dish.rotation_degrees = Vector3(35, 40, 0)
	_box(Vector3(0.05, 0.05, 0.05), Vector3(0.25, 5.3, 0.2), Art.indicator(Color(1.0, 0.35, 0.25), 2.0))


func _box(size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(mesh, pos, material)


func _cyl(top: float, bottom: float, height: float, pos: Vector3, material: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 28
	mesh.rings = 1
	var node := _add(mesh, pos, material)
	node.rotation_degrees = rot
	return node


func _add(mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = material
	add_child(node)
	return node
