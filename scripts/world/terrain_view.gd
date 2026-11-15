class_name TerrainView
extends Node3D
## Terrain built from immutable map data: one quad per cell with corner heights averaged from
## neighbouring cells, smooth rust colour variation, a decorative backdrop beyond the map, rock
## clusters on impassable ground and outside the map, and a subtle 1 m planning grid.
## Purely presentational: routing, placement and picking never read these meshes, and nothing
## here creates collision. Decorative rocks are only placed on impassable cells or outside the
## map bounds, so they never sit on ground the player can build on or route through.

const COLOR_BUILDABLE := Color(0.66, 0.36, 0.21)
const COLOR_NOT_BUILDABLE := Color(0.55, 0.32, 0.21)
const COLOR_IMPASSABLE := Color(0.31, 0.20, 0.16)
const COLOR_APRON := Color(0.56, 0.46, 0.39)
const COLOR_DUST := Color(0.78, 0.50, 0.32)
const COLOR_RUST := Color(0.47, 0.23, 0.14)
const COLOR_FAR := Color(0.50, 0.30, 0.20)
const GRID_QUIET := Color(0.12, 0.06, 0.04, 0.13)
const GRID_PLANNING := Color(0.98, 0.86, 0.66, 0.30)

var map: RefCounted
var _surface: MeshInstance3D
var _grid: MeshInstance3D
var _skirt: MeshInstance3D
var _rocks: MultiMeshInstance3D
var _grid_material: StandardMaterial3D
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()


func build(map_data: RefCounted) -> void:
	map = map_data
	for child in get_children():
		child.queue_free()
	var seed_value := hash(str(map.id)) & 0x7fffffff
	_noise.seed = seed_value
	_noise.frequency = 0.07
	_noise.fractal_octaves = 3
	_detail.seed = seed_value + 17
	_detail.frequency = 0.55
	_surface = MeshInstance3D.new()
	_surface.name = "Surface"
	_surface.mesh = _build_surface()
	_surface.material_override = _ground_material()
	add_child(_surface)

	_grid = MeshInstance3D.new()
	_grid.name = "Grid"
	_grid.mesh = _build_grid()
	_grid_material = StandardMaterial3D.new()
	_grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid_material.albedo_color = GRID_QUIET
	_grid.material_override = _grid_material
	_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grid)

	_skirt = MeshInstance3D.new()
	_skirt.name = "Skirt"
	_skirt.mesh = _build_skirt()
	_skirt.material_override = _ground_material()
	add_child(_skirt)

	_rocks = MultiMeshInstance3D.new()
	_rocks.name = "Rocks"
	_rocks.multimesh = _build_rocks()
	add_child(_rocks)


func set_grid_visible(visible_grid: bool) -> void:
	if _grid != null:
		_grid.visible = visible_grid


func is_grid_visible() -> bool:
	return _grid != null and _grid.visible


func set_grid_emphasis(planning: bool) -> void:
	## The grid is a quiet planning aid; it brightens only while a module is being placed.
	if _grid_material != null:
		_grid_material.albedo_color = GRID_PLANNING if planning else GRID_QUIET


func corner_height(x: int, z: int) -> float:
	## Height at the grid vertex (x, z), averaged from the up-to-four touching cells.
	var total := 0.0
	var count := 0
	for dx in [-1, 0]:
		for dz in [-1, 0]:
			var cell := [x + dx, z + dz]
			if map.in_bounds(cell):
				total += map.height_at(cell)
				count += 1
	return total / count if count > 0 else map.default_height_m


func surface_height(world_x: float, world_z: float) -> float:
	var cell := [int(floor(world_x)), int(floor(world_z))]
	return map.height_at(cell) if map.in_bounds(cell) else map.default_height_m


static func _ground_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.97
	material.metallic = 0.0
	return material


func _ground_tone(x: float, z: float) -> Color:
	## Smooth regional dust/rust variation plus fine speckle; deterministic per map.
	var broad := (_noise.get_noise_2d(x, z) + 1.0) * 0.5
	var fine := _detail.get_noise_2d(x, z) * 0.06
	return COLOR_RUST.lerp(COLOR_DUST, clampf(broad, 0.0, 1.0)).lightened(fine)


func _cell_color(cell: Array, x: float, z: float) -> Color:
	var passable: bool = map.is_passable(cell)
	var buildable: bool = map.is_buildable(cell)
	var tone := _ground_tone(x, z)
	if not passable:
		return COLOR_IMPASSABLE.lerp(tone, 0.25)
	if not buildable:
		var base := COLOR_NOT_BUILDABLE if map.height_at(cell) != map.default_height_m else COLOR_APRON
		return base.lerp(tone, 0.35)
	return COLOR_BUILDABLE.lerp(tone, 0.6)


func _build_surface() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in map.height:
		for x in map.width:
			var cell := [x, z]
			var h00 := corner_height(x, z)
			var h10 := corner_height(x + 1, z)
			var h01 := corner_height(x, z + 1)
			var h11 := corner_height(x + 1, z + 1)
			var p00 := Vector3(x, h00, z)
			var p10 := Vector3(x + 1, h10, z)
			var p01 := Vector3(x, h01, z + 1)
			var p11 := Vector3(x + 1, h11, z + 1)
			var c00 := _cell_color(cell, x, z)
			var c10 := _cell_color(cell, x + 1, z)
			var c01 := _cell_color(cell, x, z + 1)
			var c11 := _cell_color(cell, x + 1, z + 1)
			_triangle(tool, [p00, p01, p10], [c00, c01, c10])
			_triangle(tool, [p10, p01, p11], [c10, c01, c11])
	tool.generate_normals()
	return tool.commit()


func _build_skirt() -> ArrayMesh:
	## Rolling backdrop beyond the playable map. It stays just below the map surface inside the
	## bounds and rises gently with distance, giving the plain a horizon and a sense of scale.
	var pad := float(maxi(map.width, map.height)) * 1.6 + 20.0
	var step := 2.0
	var x0 := -pad
	var z0 := -pad
	var nx := int(ceil((map.width + 2.0 * pad) / step))
	var nz := int(ceil((map.height + 2.0 * pad) / step))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := []
	var colors := []
	for j in nz + 1:
		for i in nx + 1:
			var x := x0 + i * step
			var z := z0 + j * step
			var dx := maxf(maxf(-x, x - map.width), 0.0)
			var dz := maxf(maxf(-z, z - map.height), 0.0)
			var outside := sqrt(dx * dx + dz * dz)
			var rise := smoothstep(2.0, 40.0, outside)
			var hills := (_noise.get_noise_2d(x * 0.6, z * 0.6) + 0.6) * 5.0 * rise + rise * rise * 6.0
			var y: float = map.default_height_m - 0.12 + maxf(hills, 0.0)
			points.append(Vector3(x, y, z))
			var tone := _ground_tone(x, z).lerp(COLOR_FAR, clampf(outside / 70.0, 0.0, 0.7))
			colors.append(tone.darkened(clampf(hills * 0.02, 0.0, 0.15)))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			_triangle(tool, [points[a], points[c], points[b]], [colors[a], colors[c], colors[b]])
			_triangle(tool, [points[b], points[c], points[d]], [colors[b], colors[c], colors[d]])
	tool.generate_normals()
	return tool.commit()


func _build_rocks() -> MultiMesh:
	var rock := SphereMesh.new()
	rock.radius = 0.5
	rock.height = 0.7
	rock.radial_segments = 7
	rock.rings = 4
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	rock.material = material
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(map.id) + ":rocks")
	var transforms: Array = []
	var colors: Array = []
	var place := func(center: Vector3, spread: float, count: int, size: float) -> void:
		for k in count:
			var offset := Vector3(rng.randf_range(-spread, spread), 0.0, rng.randf_range(-spread, spread))
			var s := size * rng.randf_range(0.45, 1.1)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.8, 1.4), s * rng.randf_range(0.5, 0.9), s))
			transforms.append(Transform3D(basis, center + offset + Vector3(0, s * 0.08, 0)))
			colors.append(COLOR_IMPASSABLE.lerp(Color(0.42, 0.30, 0.25), rng.randf()).darkened(rng.randf_range(0.0, 0.25)))
	# Inside the map: only impassable ground, kept within its cell.
	for z in map.height:
		for x in map.width:
			var cell := [x, z]
			if not map.is_passable(cell):
				var y: float = map.height_at(cell)
				place.call(Vector3(x + 0.5, y, z + 0.5), 0.25, rng.randi_range(1, 2), 0.42)
	# Outside the map: scattered boulder fields that frame the plain.
	var clusters: int = 26 + (map.width + map.height) / 2
	for k in clusters:
		var angle := rng.randf() * TAU
		var radius: float = maxf(map.width, map.height) * 0.5 + rng.randf_range(4.0, 30.0)
		var cx: float = map.width * 0.5 + cos(angle) * radius
		var cz: float = map.height * 0.5 + sin(angle) * radius
		if cx > -1.5 and cx < map.width + 1.5 and cz > -1.5 and cz < map.height + 1.5:
			continue
		place.call(Vector3(cx, map.default_height_m - 0.1, cz), 1.6, rng.randi_range(2, 6), rng.randf_range(0.5, 1.5))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = rock
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_color(i, colors[i])
	return multimesh


func _triangle(tool: SurfaceTool, points: Array, colors: Array) -> void:
	for i in 3:
		tool.set_color(colors[i])
		tool.add_vertex(points[i])


func _build_grid() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_LINES)
	var lift := 0.02
	for x in map.width + 1:
		for z in map.height:
			tool.add_vertex(Vector3(x, corner_height(x, z) + lift, z))
			tool.add_vertex(Vector3(x, corner_height(x, z + 1) + lift, z + 1))
	for z in map.height + 1:
		for x in map.width:
			tool.add_vertex(Vector3(x, corner_height(x, z) + lift, z))
			tool.add_vertex(Vector3(x + 1, corner_height(x + 1, z) + lift, z))
	return tool.commit()
