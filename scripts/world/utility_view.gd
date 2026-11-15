class_name UtilityView
extends Node3D
## Visualizes the single shared base utility network. Contract section 7: v1 assumes one shared
## electrical/resource distribution network for commissioned buildings, which corridors and
## utility lines may visualize; separate grids are not simulated and must not be implied.
##
## Each non-destroyed building gets a surface line from the base airlock to its nearest reachable
## entrance, following the authoritative BFS route from WorldService.query_route. Colour shows the
## building's power state from the snapshot. Lines are rebuilt only when the blocked-cell set or
## the building set changes; colours update on every snapshot.

const SERVED := Color(0.32, 0.72, 0.82)
const PARTIAL := Color(1.0, 0.72, 0.15)
const UNSERVED := Color(0.95, 0.25, 0.25)
const IDLE := Color(0.55, 0.55, 0.58)
const CONSTRUCTING := Color(0.95, 0.8, 0.3)
const WIDTH := 0.07
const LIFT := 0.06

var world_service: RefCounted
var terrain: Node3D
var _lines: Dictionary = {}  # building_id -> {node, key, material, reachable}
var _blocked_key: String = ""


func setup(service: RefCounted, terrain_view: Node3D) -> void:
    world_service = service
    terrain = terrain_view


func reset() -> void:
    for entry in _lines.values():
        entry.node.queue_free()
    _lines.clear()
    _blocked_key = ""


func apply_snapshot(snapshot: Dictionary) -> void:
    var buildings: Dictionary = snapshot.get("buildings", {})
    var blocked_key := JSON.stringify(world_service.blocked_cells(snapshot))
    var geometry_changed := blocked_key != _blocked_key
    _blocked_key = blocked_key
    for building_id in _lines.keys():
        if not buildings.has(building_id) or buildings[building_id].get("lifecycle") == "destroyed":
            _lines[building_id].node.queue_free()
            _lines.erase(building_id)
    var ids: Array = buildings.keys()
    ids.sort()
    for building_id in ids:
        var building: Dictionary = buildings[building_id]
        if building.get("lifecycle") == "destroyed":
            continue
        var key := "%s|%d|%d|%d" % [building.definition_id, int(building.cell[0]), int(building.cell[1]), int(building.rotation_quarters)]
        var entry: Variant = _lines.get(building_id)
        if entry == null or entry.key != key or geometry_changed:
            if entry != null:
                entry.node.queue_free()
            entry = _build_line(building, snapshot)
            entry.key = key
            _lines[building_id] = entry
        entry.material.albedo_color = _color_for(building)


func unreachable_buildings() -> Array:
    var result: Array = []
    for building_id in _lines:
        if not _lines[building_id].reachable:
            result.append(building_id)
    result.sort()
    return result


func _build_line(building: Dictionary, snapshot: Dictionary) -> Dictionary:
    var root := Node3D.new()
    root.name = building.id + "_utility"
    add_child(root)
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = IDLE
    var airlock: Array = world_service.map.base_airlock_cell
    var best: Dictionary = {}
    for entrance in world_service.building_cells(building).entrance_cells:
        var route: Dictionary = world_service.query_route({"from_cell": airlock, "to_cell": entrance}, snapshot)
        if route.reachable and (best.is_empty() or route.distance_m < best.distance_m):
            best = route
    var reachable := not best.is_empty()
    if reachable:
        var points: Array = best.waypoints_m
        for index in points.size() - 1:
            root.add_child(_segment(points[index], points[index + 1], material))
        if points.size() == 1:
            root.add_child(_segment(points[0], points[0], material))
    return {"node": root, "key": "", "material": material, "reachable": reachable}


func _segment(a: Array, b: Array, material: StandardMaterial3D) -> MeshInstance3D:
    var start := Vector3(float(a[0]), float(a[1]) + LIFT, float(a[2]))
    var finish := Vector3(float(b[0]), float(b[1]) + LIFT, float(b[2]))
    var instance := MeshInstance3D.new()
    var box := BoxMesh.new()
    var length := maxf(start.distance_to(finish), WIDTH)
    box.size = Vector3(WIDTH, 0.03, length + WIDTH)
    instance.mesh = box
    instance.material_override = material
    instance.position = (start + finish) * 0.5
    if start.distance_to(finish) > 0.001:
        instance.look_at_from_position(instance.position, finish, Vector3.UP)
    return instance


static func _color_for(building: Dictionary) -> Color:
    if building.get("lifecycle") == "constructing":
        return CONSTRUCTING
    if not bool(building.get("enabled", true)) or building.get("blocking_codes", []).has("disabled"):
        return IDLE
    var requested := float(building.get("power_requested_kw", 0.0))
    var served := float(building.get("power_served_kw", 0.0))
    if requested > 0.0:
        if served >= requested - 1e-9:
            return SERVED
        return PARTIAL if served > 0.0 else UNSERVED
    if building.get("blocking_codes", []).has("no_power"):
        return UNSERVED
    return SERVED if float(building.get("operating_fraction", 0.0)) > 0.0 else IDLE
