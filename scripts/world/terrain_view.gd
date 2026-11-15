class_name TerrainView
extends Node3D
## Blockout terrain built from immutable map data: one quad per cell with corner heights averaged
## from neighbouring cells, vertex colours by terrain flag, and a toggleable 1 m grid overlay.
## Purely presentational; routing and placement never read this mesh.

const COLOR_BUILDABLE := Color(0.72, 0.40, 0.24)
const COLOR_NOT_BUILDABLE := Color(0.50, 0.33, 0.24)
const COLOR_IMPASSABLE := Color(0.33, 0.21, 0.17)
const COLOR_APRON := Color(0.58, 0.47, 0.40)

var map: RefCounted
var _surface: MeshInstance3D
var _grid: MeshInstance3D
var _skirt: MeshInstance3D


func build(map_data: RefCounted) -> void:
    map = map_data
    for child in get_children():
        child.queue_free()
    _surface = MeshInstance3D.new()
    _surface.name = "Surface"
    _surface.mesh = _build_surface()
    var material := StandardMaterial3D.new()
    material.vertex_color_use_as_albedo = true
    material.roughness = 1.0
    material.metallic = 0.0
    _surface.material_override = material
    add_child(_surface)

    _grid = MeshInstance3D.new()
    _grid.name = "Grid"
    _grid.mesh = _build_grid()
    var grid_material := StandardMaterial3D.new()
    grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    grid_material.albedo_color = Color(0.1, 0.06, 0.05, 0.35)
    _grid.material_override = grid_material
    add_child(_grid)

    _skirt = MeshInstance3D.new()
    _skirt.name = "Skirt"
    var plane := PlaneMesh.new()
    plane.size = Vector2(map.width * 6.0, map.height * 6.0)
    _skirt.mesh = plane
    _skirt.position = Vector3(map.width * 0.5, map.default_height_m - 0.08, map.height * 0.5)
    var skirt_material := StandardMaterial3D.new()
    skirt_material.albedo_color = COLOR_IMPASSABLE.darkened(0.25)
    skirt_material.roughness = 1.0
    _skirt.material_override = skirt_material
    add_child(_skirt)


func set_grid_visible(visible_grid: bool) -> void:
    if _grid != null:
        _grid.visible = visible_grid


func is_grid_visible() -> bool:
    return _grid != null and _grid.visible


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


func _cell_color(cell: Array) -> Color:
    var passable: bool = map.is_passable(cell)
    var buildable: bool = map.is_buildable(cell)
    var base: Color
    if not passable:
        base = COLOR_IMPASSABLE
    elif not buildable:
        base = COLOR_NOT_BUILDABLE if map.height_at(cell) != map.default_height_m else COLOR_APRON
    else:
        base = COLOR_BUILDABLE
    # Deterministic per-cell speckle so the plain is not a flat colour.
    var hash_value := (int(cell[0]) * 73856093) ^ (int(cell[1]) * 19349663)
    var noise := float(posmod(hash_value, 256)) / 255.0
    return base.lightened((noise - 0.5) * 0.12)


func _build_surface() -> ArrayMesh:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    for z in map.height:
        for x in map.width:
            var cell := [x, z]
            var color := _cell_color(cell)
            var h00 := corner_height(x, z)
            var h10 := corner_height(x + 1, z)
            var h01 := corner_height(x, z + 1)
            var h11 := corner_height(x + 1, z + 1)
            var p00 := Vector3(x, h00, z)
            var p10 := Vector3(x + 1, h10, z)
            var p01 := Vector3(x, h01, z + 1)
            var p11 := Vector3(x + 1, h11, z + 1)
            _triangle(tool, p00, p01, p10, color)
            _triangle(tool, p10, p01, p11, color)
    tool.generate_normals()
    return tool.commit()


func _triangle(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
    for point in [a, b, c]:
        tool.set_color(color)
        tool.add_vertex(point)


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
