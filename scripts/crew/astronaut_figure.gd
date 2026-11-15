extends Node3D
## A round, chunky cartoon astronaut built from primitive meshes: a big head inside a glass
## bubble helmet, a soft capsule suit, stubby limbs and a life-support pack. Faces +Z.
## Presentation only. Call apply_look(look) with a look from astronaut_look.gd.
##
## Animation: set `mode` to "idle", "walk", "wave" or "cheer". Animation advances by itself
## unless `manual_time` is true, in which case call pose(t) (used by tests and the intro).

const Look := preload("res://scripts/crew/astronaut_look.gd")

const HEAD_RADIUS := 0.15
const HELMET_RADIUS := 0.235
const HEAD_SCALE := 1.22

var mode := "idle"
var manual_time := false
var anim_time := 0.0
## Phase offset so a group of figures does not move in lockstep.
var phase := 0.0

var look: Dictionary = {}
var _rig: Node3D
var _hips: Array[Node3D] = []
var _shoulders: Array[Node3D] = []
var _head: Node3D
var _torso_y := 0.0
var _materials := {}


func _ready() -> void:
	if look.is_empty():
		apply_look(Look.default_look())


func apply_look(new_look: Dictionary) -> void:
	look = Look.sanitize(new_look)
	if _rig != null:
		_rig.free()
	_hips.clear()
	_shoulders.clear()
	_materials.clear()
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_build()
	pose(anim_time)


## Total height of the helmet top above the feet, in metres.
func figure_height() -> float:
	var h: float = Look.option("height", look.height).scale
	return 0.89 * h + (0.16 + HELMET_RADIUS + 0.015) * HEAD_SCALE


func _process(delta: float) -> void:
	if manual_time or _rig == null:
		return
	anim_time += delta
	pose(anim_time)


func pose(t: float) -> void:
	anim_time = t
	if _rig == null or _hips.size() < 2:
		return
	var s := t + phase
	var swing := 0.0
	var bob := 0.0
	var arm_l := 0.0
	var arm_r := 0.0
	# Shoulder 0 sits at -X, shoulder 1 at +X; positive Z roll swings the +X arm outward.
	var arm_l_out := -0.12
	var arm_r_out := 0.12
	match mode:
		"walk":
			swing = sin(s * 7.0) * 0.55
			bob = absf(sin(s * 7.0)) * 0.035
			arm_l = -swing * 0.8
			arm_r = swing * 0.8
		"wave":
			bob = sin(s * 2.0) * 0.008
			arm_l = sin(s * 1.5) * 0.05
			arm_r = -2.6
			arm_r_out = 0.35 + sin(s * 8.0) * 0.35
		"cheer":
			bob = absf(sin(s * 5.0)) * 0.05
			arm_l = -2.8
			arm_r = -2.8
			arm_l_out = -0.3 - sin(s * 5.0) * 0.15
			arm_r_out = 0.3 + sin(s * 5.0) * 0.15
		_:
			bob = sin(s * 2.0) * 0.008
			arm_l = sin(s * 1.5) * 0.05
			arm_r = -arm_l
	_hips[0].rotation.x = swing
	_hips[1].rotation.x = -swing
	_shoulders[0].rotation = Vector3(arm_l, 0.0, arm_l_out)
	_shoulders[1].rotation = Vector3(arm_r, 0.0, arm_r_out)
	_rig.position.y = bob
	if _head != null:
		_head.rotation.z = sin(s * 1.3) * 0.04 if mode != "walk" else 0.0
		_head.rotation.y = sin(s * 0.7) * 0.12 if mode == "idle" else 0.0


func _build() -> void:
	var h: float = Look.option("height", look.height).scale
	var w: float = Look.option("build", look.build).width
	var suit := _mat("suit", Look.color(look, "suit"), 0.75)
	var accent := _mat("accent", Look.color(look, "accent"), 0.55)
	var skin := _mat("skin", Look.color(look, "skin"), 0.8)
	var hair := _mat("hair", Look.color(look, "hair_color"), 0.9)
	var trim := _mat("trim", Color("#9aa0a8"), 0.4, 0.5)
	var dark := _mat("dark", Color("#2b2d33"), 0.85)
	var pack := _mat("pack", Look.color(look, "suit").darkened(0.12), 0.8)
	# Legs swing from hip pivots; boots ride with them.
	var hip_y := 0.44 * h
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.09 * w * side, hip_y, 0.0)
		_rig.add_child(hip)
		_hips.append(hip)
		_add(hip, _capsule(0.078 * w, 0.36 * h), Vector3(0, -0.17 * h, 0), suit)
		_add(hip, _capsule(0.082 * w, 0.1), Vector3(0, -0.2 * h, 0), accent).scale = Vector3(1, 0.4, 1)
		_add(hip, _box(Vector3(0.15 * w, 0.11, 0.22)), Vector3(0, -hip_y + 0.055, 0.025), dark)
	# Torso: a soft capsule with a belt, chest panel and shoulder patch.
	_torso_y = 0.64 * h
	_add(_rig, _capsule(0.17 * w, 0.52 * h), Vector3(0, _torso_y, 0), suit).scale = Vector3(1, 1, 0.82)
	_add(_rig, _cylinder(0.173 * w, 0.05), Vector3(0, 0.47 * h, 0), accent).scale = Vector3(1, 1, 0.84)
	_add(_rig, _box(Vector3(0.15 * w, 0.09, 0.03)), Vector3(0, 0.66 * h, 0.135 * w), trim)
	for k in 3:
		var light := _add(_rig, _sphere(0.012), Vector3((k - 1) * 0.035 * w, 0.66 * h, 0.152 * w),
			_glow([Color("#5cff8a"), Color("#ffd447"), Color("#4fd2ff")][k]))
		light.name = "ChestLight%d" % k
	var patch := _add(_rig, _cylinder(0.045, 0.012), Vector3(0.165 * w, 0.76 * h, 0.03), accent)
	patch.rotation.z = PI * 0.5
	# Life-support pack.
	_add(_rig, _box(Vector3(0.3 * w, 0.4 * h, 0.15)), Vector3(0, 0.67 * h, -0.135 * w - 0.07), pack)
	_add(_rig, _box(Vector3(0.31 * w, 0.05, 0.16)), Vector3(0, 0.67 * h + 0.2 * h, -0.135 * w - 0.07), accent)
	# Arms swing from shoulder pivots; gloves ride with them.
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3((0.17 * w + 0.045) * side, 0.8 * h, 0.0)
		_rig.add_child(shoulder)
		_shoulders.append(shoulder)
		_add(shoulder, _sphere(0.07 * w), Vector3.ZERO, suit)
		_add(shoulder, _capsule(0.06 * w, 0.34 * h), Vector3(0, -0.15 * h, 0), suit)
		_add(shoulder, _sphere(0.068), Vector3(0, -0.32 * h, 0), accent)
	# Neck ring, then the head assembly (head, face, hair, helmet) on its own pivot.
	var ring := _add(_rig, _torus(0.085, 0.135), Vector3(0, 0.89 * h, 0), trim)
	ring.scale = Vector3(1, 1.6, 1)
	_head = Node3D.new()
	_head.name = "Head"
	# An oversized head and helmet give the friendly, chunky cartoon proportions.
	_head.position = Vector3(0, 0.89 * h + 0.16 * HEAD_SCALE, 0)
	_head.scale = Vector3.ONE * HEAD_SCALE
	_rig.add_child(_head)
	_add(_head, _sphere(HEAD_RADIUS), Vector3.ZERO, skin)
	_build_face(skin, hair)
	_build_hair(hair)
	_build_helmet(trim, accent)


func _build_face(skin: Material, hair: Material) -> void:
	var white := _mat("eye_white", Color("#fbfbf7"), 0.3)
	var iris := _mat("iris", Look.color(look, "eye_color"), 0.3)
	var shine := _glow(Color.WHITE)
	for side in [-1.0, 1.0]:
		var eye := _add(_head, _sphere(0.03), Vector3(0.052 * side, 0.02, 0.128), white)
		eye.scale = Vector3(0.9, 1.1, 0.6)
		_add(_head, _sphere(0.017), Vector3(0.052 * side, 0.016, 0.146), iris)
		_add(_head, _sphere(0.005), Vector3(0.052 * side + 0.006, 0.024, 0.152), shine)
		var brow := _add(_head, _box(Vector3(0.045, 0.011, 0.012)), Vector3(0.054 * side, 0.068, 0.133), hair)
		brow.rotation.z = -0.12 * side
		# Ears.
		_add(_head, _sphere(0.032), Vector3(0.148 * side, 0.0, 0.0), skin).scale = Vector3(0.5, 1, 0.8)
	var nose := _add(_head, _sphere(0.022), Vector3(0, -0.012, 0.15), _mat("nose", Look.color(look, "skin").darkened(0.08), 0.8))
	nose.scale = Vector3(1, 0.9, 0.8)
	var mouth := _add(_head, _capsule(0.009, 0.06), Vector3(0, -0.058, 0.138), _mat("mouth", Color("#5a2a2a"), 0.8))
	mouth.rotation.z = PI * 0.5
	for side in [-1.0, 1.0]:
		# Upturned mouth corners make the smile.
		var corner := _add(_head, _capsule(0.008, 0.026), Vector3(0.032 * side, -0.05, 0.133), _materials.mouth)
		corner.rotation.z = 0.9 * side
	match str(look.facial_hair):
		"mustache":
			for side in [-1.0, 1.0]:
				var tuft := _add(_head, _capsule(0.012, 0.05), Vector3(0.02 * side, -0.036, 0.147), hair)
				tuft.rotation.z = (PI * 0.5) + 0.35 * side
		"goatee":
			_add(_head, _sphere(0.032), Vector3(0, -0.105, 0.11), hair).scale = Vector3(1, 1.2, 0.8)
		"beard":
			var beard := _add(_head, _sphere(0.105), Vector3(0, -0.085, 0.045), hair)
			beard.scale = Vector3(1.25, 0.75, 0.85)
			for side in [-1.0, 1.0]:
				_add(_head, _capsule(0.012, 0.05), Vector3(0.022 * side, -0.036, 0.146), hair).rotation.z = (PI * 0.5) + 0.3 * side
	match str(look.glasses):
		"round":
			var frame := _mat("frame", Color("#1d1d22"), 0.4, 0.3)
			for side in [-1.0, 1.0]:
				var lens := _add(_head, _torus(0.032, 0.039), Vector3(0.052 * side, 0.018, 0.158), frame)
				lens.rotation.x = PI * 0.5
			_add(_head, _box(Vector3(0.03, 0.007, 0.007)), Vector3(0, 0.024, 0.162), frame)
		"square":
			var frame := _mat("frame", Color("#1d1d22"), 0.4, 0.3)
			for side in [-1.0, 1.0]:
				var cx: float = 0.054 * side
				_add(_head, _box(Vector3(0.07, 0.008, 0.008)), Vector3(cx, 0.048, 0.157), frame)
				_add(_head, _box(Vector3(0.07, 0.008, 0.008)), Vector3(cx, -0.008, 0.157), frame)
				_add(_head, _box(Vector3(0.008, 0.056, 0.008)), Vector3(cx - 0.035, 0.02, 0.155), frame)
				_add(_head, _box(Vector3(0.008, 0.056, 0.008)), Vector3(cx + 0.035, 0.02, 0.155), frame)
			_add(_head, _box(Vector3(0.022, 0.007, 0.007)), Vector3(0, 0.03, 0.162), frame)


func _cap(hair: Material, radius: float, tilt: float) -> MeshInstance3D:
	## A hemisphere over the crown, tilted back so the forehead and eyes stay clear.
	var mesh := _sphere(radius)
	mesh.is_hemisphere = true
	mesh.height = radius
	var node := _add(_head, mesh, Vector3(0, 0.005, -0.004), hair)
	node.rotation.x = -tilt
	return node


func _build_hair(hair: Material) -> void:
	match str(look.hair_style):
		"short":
			_cap(hair, 0.158, 0.42)
			_add(_head, _sphere(0.05), Vector3(-0.06, 0.1, 0.09), hair).scale = Vector3(1.6, 0.6, 0.9)
		"buzz":
			_cap(hair, 0.154, 0.55)
		"bald":
			pass
		"curly", "afro":
			var big: bool = look.hair_style == "afro"
			var shell_r := 0.165 if big else 0.152
			var curl := 0.062 if big else 0.045
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for i in 46 if big else 30:
				var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1), rng.randf_range(-1, 0.55)).normalized()
				if dir.z > 0.42 and dir.y < 0.62:
					continue # Keep the face clear.
				_add(_head, _sphere(curl * rng.randf_range(0.85, 1.1)), dir * shell_r + Vector3(0, 0.012, -0.01), hair)
		"bun":
			_cap(hair, 0.158, 0.45)
			_add(_head, _sphere(0.058), Vector3(0, 0.15, -0.06), hair)
		"ponytail":
			_cap(hair, 0.158, 0.45)
			_add(_head, _sphere(0.045), Vector3(0, 0.05, -0.165), hair)
			var tail := _add(_head, _capsule(0.035, 0.15), Vector3(0, -0.04, -0.18), hair)
			tail.rotation.x = 0.25
		"long":
			_cap(hair, 0.16, 0.38)
			var back := _add(_head, _capsule(0.12, 0.3), Vector3(0, -0.07, -0.085), hair)
			back.scale = Vector3(1.15, 1, 0.55)
			for side in [-1.0, 1.0]:
				_add(_head, _capsule(0.04, 0.2), Vector3(0.13 * side, -0.07, -0.01), hair)
		"bob":
			_cap(hair, 0.162, 0.38)
			for side in [-1.0, 1.0]:
				_add(_head, _sphere(0.07), Vector3(0.115 * side, -0.035, -0.035), hair).scale = Vector3(0.8, 1.1, 1.1)
			_add(_head, _sphere(0.1), Vector3(0, -0.03, -0.09), hair).scale = Vector3(1.3, 1, 0.8)
		"braids":
			_cap(hair, 0.158, 0.4)
			for side in [-1.0, 1.0]:
				for k in 3:
					_add(_head, _sphere(0.03), Vector3(0.125 * side, -0.05 - k * 0.045, -0.045), hair)
		"spiky":
			_cap(hair, 0.155, 0.5)
			var rng := RandomNumberGenerator.new()
			rng.seed = 3
			for i in 9:
				var dir := Vector3(rng.randf_range(-0.7, 0.7), 1.0, rng.randf_range(-0.7, 0.25)).normalized()
				var spike := MeshInstance3D.new()
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = 0.035
				cone.height = 0.08
				spike.mesh = cone
				spike.material_override = hair
				spike.position = dir * 0.16
				spike.basis = Basis(Quaternion(Vector3.UP, dir))
				_head.add_child(spike)
		"headscarf":
			# A hood that wraps the crown, sides and neck while leaving the face clear.
			var scarf := _add(_head, _sphere(0.18), Vector3(0, 0.012, -0.046), hair)
			scarf.scale = Vector3(1.0, 1.02, 1.0)
			var drape := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.12
			cone.bottom_radius = 0.17
			cone.height = 0.14
			drape.mesh = cone
			drape.material_override = hair
			drape.position = Vector3(0, -0.13, -0.03)
			_head.add_child(drape)


func _build_helmet(trim: Material, accent: Material) -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.78, 0.9, 1.0, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.2
	glass.rim_enabled = true
	glass.rim = 0.8
	glass.rim_tint = 0.3
	glass.cull_mode = BaseMaterial3D.CULL_BACK
	var helmet := _add(_head, _sphere(HELMET_RADIUS), Vector3(0, 0.015, 0.012), glass)
	helmet.name = "Helmet"
	helmet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glint := StandardMaterial3D.new()
	glint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint.albedo_color = Color(1, 1, 1, 0.55)
	glint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var spot := _add(_head, _sphere(0.04), Vector3(-0.1, 0.13, 0.17), glint)
	spot.scale = Vector3(1.4, 0.7, 0.4)
	spot.rotation.z = 0.6
	spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Helmet lamp and comm stub on the sides.
	_add(_head, _box(Vector3(0.05, 0.045, 0.07)), Vector3(0.235, 0.03, 0.0), trim)
	_add(_head, _sphere(0.018), Vector3(0.236, 0.03, 0.04), _glow(Color("#fff3c4")))
	_add(_head, _box(Vector3(0.04, 0.06, 0.05)), Vector3(-0.235, 0.0, 0.0), accent)


func _mat(key: String, albedo: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	material.metallic = metallic
	_materials[key] = material
	return material


func _glow(albedo: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = albedo
	return material


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	return mesh


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = 16
	mesh.rings = 4
	return mesh


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	return mesh


func _torus(inner: float, outer: float) -> TorusMesh:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 20
	mesh.ring_segments = 8
	return mesh


func _add(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node
