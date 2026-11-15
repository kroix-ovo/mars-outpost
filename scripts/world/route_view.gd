class_name RouteView
extends Node3D
## Draws expedition routes from snapshot `expeditions[id].route_waypoints_m` with a progress
## marker at `route_progress_m`, plus one advisory preview route (hovered or selected site).
## Crew figures themselves belong to Task 03 (scenes/crew); this node only shows the
## authoritative path and how far along it the team is.

const OUTBOUND := Color(0.35, 0.75, 1.0)
const RETURNING := Color(0.55, 0.95, 0.55)
const STRANDED := Color(1.0, 0.3, 0.3)
const DONE := Color(0.6, 0.6, 0.65, 0.5)
const PREVIEW := Color(1.0, 1.0, 1.0, 0.9)
const PREVIEW_BLOCKED := Color(1.0, 0.35, 0.3, 0.9)

var _lines: Dictionary = {}  # expedition_id -> MeshInstance3D
var _markers: Dictionary = {}  # expedition_id -> MeshInstance3D
var _preview: MeshInstance3D
var _preview_end: MeshInstance3D


func reset() -> void:
    for id in _lines.keys():
        _lines[id].queue_free()
        _markers[id].queue_free()
    _lines.clear()
    _markers.clear()
    clear_preview()


func apply_snapshot(snapshot: Dictionary) -> void:
    var expeditions: Dictionary = snapshot.get("expeditions", {})
    for id in _lines.keys():
        if not expeditions.has(id):
            _lines[id].queue_free()
            _markers[id].queue_free()
            _lines.erase(id)
            _markers.erase(id)
    var ids: Array = expeditions.keys()
    ids.sort()
    for id in ids:
        var expedition: Dictionary = expeditions[id]
        var waypoints: Array = expedition.get("route_waypoints_m", [])
        if waypoints.size() < 1:
            continue
        if not _lines.has(id):
            _lines[id] = MeshInstance3D.new()
            _lines[id].name = id + "_route"
            add_child(_lines[id])
            var marker := MeshInstance3D.new()
            marker.name = id + "_marker"
            var sphere := SphereMesh.new()
            sphere.radius = 0.22
            sphere.height = 0.44
            marker.mesh = sphere
            add_child(marker)
            _markers[id] = marker
        var color := _color_for(str(expedition.get("status", "")))
        _lines[id].mesh = _polyline(waypoints)
        _lines[id].material_override = _unshaded(color)
        _markers[id].material_override = _unshaded(color)
        _markers[id].position = point_along(waypoints, float(expedition.get("route_progress_m", 0.0)), str(expedition.get("status", ""))) + Vector3(0.0, 0.3, 0.0)
        _markers[id].visible = expedition.get("status") in ["outbound", "returning", "stranded", "working"]


func show_preview(route: Dictionary, target_cell: Array, height: float = 0.0) -> void:
    ## Advisory route from the airlock to a hovered/selected site. An unreachable target shows a
    ## red marker only, so a missing line is never mistaken for free travel.
    clear_preview()
    var reachable: bool = route.get("reachable", false)
    _preview_end = MeshInstance3D.new()
    var ring := TorusMesh.new()
    ring.inner_radius = 0.3
    ring.outer_radius = 0.42
    _preview_end.mesh = ring
    _preview_end.position = Vector3(float(target_cell[0]) + 0.5, height + 0.1, float(target_cell[1]) + 0.5)
    _preview_end.material_override = _unshaded(PREVIEW if reachable else PREVIEW_BLOCKED)
    add_child(_preview_end)
    if reachable and route.waypoints_m.size() > 0:
        _preview = MeshInstance3D.new()
        _preview.mesh = _polyline(route.waypoints_m, 0.14)
        _preview.material_override = _unshaded(PREVIEW)
        add_child(_preview)


func clear_preview() -> void:
    if _preview != null:
        _preview.queue_free()
        _preview = null
    if _preview_end != null:
        _preview_end.queue_free()
        _preview_end = null


static func point_along(waypoints: Array, progress_m: float, status: String = "outbound") -> Vector3:
    ## Interpolates along cell-centre waypoints (1 m per edge). Returning teams walk the same
    ## polyline backwards from the far end.
    if waypoints.is_empty():
        return Vector3.ZERO
    var points: Array = []
    for w in waypoints:
        points.append(Vector3(float(w[0]), float(w[1]), float(w[2])))
    if status == "returning":
        points.reverse()
    var remaining := maxf(progress_m, 0.0)
    for index in points.size() - 1:
        var a: Vector3 = points[index]
        var b: Vector3 = points[index + 1]
        var segment := a.distance_to(b)
        if remaining <= segment or segment == 0.0:
            return a.lerp(b, 0.0 if segment == 0.0 else remaining / segment)
        remaining -= segment
    return points[points.size() - 1]


static func _unshaded(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.albedo_color = color
    return material


static func _color_for(status: String) -> Color:
    match status:
        "returning":
            return RETURNING
        "stranded":
            return STRANDED
        "completed", "failed":
            return DONE
        _:
            return OUTBOUND


static func _polyline(waypoints: Array, lift: float = 0.08) -> ArrayMesh:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_LINE_STRIP)
    for w in waypoints:
        tool.add_vertex(Vector3(float(w[0]), float(w[1]) + lift, float(w[2])))
    if waypoints.size() == 1:
        var w: Array = waypoints[0]
        tool.add_vertex(Vector3(float(w[0]), float(w[1]) + 0.3, float(w[2])))
    return tool.commit()
