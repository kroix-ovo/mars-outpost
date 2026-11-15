class_name SiteView
extends Node3D
## Renders snapshot `sites` as placeholder markers by kind, inferred from the site definition id:
## "ice" -> ice survey crystals, "survey" -> instrument tripod, anything else -> cargo crates.
## Every site carries a flag whose pennant colour shows reservation state (free / reserved /
## emptied). Read-only presentation; EVA decisions belong to Task 03.

enum Kind { CARGO, SURVEY, ICE }

const FREE := Color(0.95, 0.85, 0.25)
const RESERVED := Color(0.35, 0.75, 1.0)
const EMPTY := Color(0.55, 0.55, 0.6)

var terrain: Node3D
var _nodes: Dictionary = {}  # site_id -> Node3D
var _pennants: Dictionary = {}  # site_id -> StandardMaterial3D
var _records: Dictionary = {}


func setup(terrain_view: Node3D) -> void:
    terrain = terrain_view


func reset() -> void:
    for node in _nodes.values():
        node.queue_free()
    _nodes.clear()
    _pennants.clear()
    _records = {}


func apply_snapshot(snapshot: Dictionary) -> void:
    var sites: Dictionary = snapshot.get("sites", {})
    _records = sites
    for site_id in _nodes.keys():
        if not sites.has(site_id):
            _nodes[site_id].queue_free()
            _nodes.erase(site_id)
            _pennants.erase(site_id)
    var ids: Array = sites.keys()
    ids.sort()
    for site_id in ids:
        var site: Dictionary = sites[site_id]
        if not _nodes.has(site_id):
            _nodes[site_id] = _spawn(site_id, site)
        var remaining: Dictionary = site.get("remaining_cargo", {})
        var total := 0.0
        for amount in remaining.values():
            total += float(amount)
        var color := EMPTY if total <= 0.0 else (RESERVED if site.get("reserved_by_expedition_id") != null else FREE)
        _pennants[site_id].albedo_color = color


func site_at_cell(cell: Array) -> String:
    var ids: Array = _records.keys()
    ids.sort()
    for site_id in ids:
        var site_cell: Array = _records[site_id].cell
        if int(site_cell[0]) == int(cell[0]) and int(site_cell[1]) == int(cell[1]):
            return site_id
    return ""


func site_ids() -> Array:
    var ids: Array = _records.keys()
    ids.sort()
    return ids


func site_cell(site_id: String) -> Array:
    return _records[site_id].cell.duplicate() if _records.has(site_id) else []


static func kind_of(definition_id: String) -> int:
    var lower := definition_id.to_lower()
    if lower.contains("ice"):
        return Kind.ICE
    if lower.contains("survey"):
        return Kind.SURVEY
    return Kind.CARGO


static func kind_name(kind: int) -> String:
    match kind:
        Kind.ICE:
            return "ice survey"
        Kind.SURVEY:
            return "survey"
        _:
            return "cargo"


func describe(site_id: String) -> String:
    if not _records.has(site_id):
        return ""
    var site: Dictionary = _records[site_id]
    var parts: PackedStringArray = []
    for resource in site.get("remaining_cargo", {}):
        parts.append("%s %s" % [str(site.remaining_cargo[resource]), resource])
    var reserved: Variant = site.get("reserved_by_expedition_id")
    var cargo := ", ".join(parts) if not parts.is_empty() else "none"
    return "%s [%s] cargo: %s%s" % [site_id, kind_name(kind_of(site.definition_id)), cargo, ("  reserved by " + str(reserved)) if reserved != null else ""]


# ---------------------------------------------------------------- markers

func _spawn(site_id: String, site: Dictionary) -> Node3D:
    var root := Node3D.new()
    root.name = site_id
    var x := float(site.cell[0]) + 0.5
    var z := float(site.cell[1]) + 0.5
    var y: float = terrain.surface_height(x, z) if terrain != null else 0.0
    root.position = Vector3(x, y, z)
    match kind_of(str(site.get("definition_id", ""))):
        Kind.ICE:
            _add_ice(root)
        Kind.SURVEY:
            _add_survey(root)
        _:
            _add_cargo(root)
    _add_flag(root, site_id)
    add_child(root)
    return root


func _material(color: Color, rough: float = 0.6, metal: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = rough
    material.metallic = metal
    return material


func _add_cargo(root: Node3D) -> void:
    var crate_material := _material(Color(0.82, 0.82, 0.86))
    for offset in [Vector3(-0.22, 0.2, -0.18), Vector3(0.2, 0.18, 0.15), Vector3(-0.05, 0.55, 0.0)]:
        var crate := MeshInstance3D.new()
        var box := BoxMesh.new()
        box.size = Vector3(0.42, 0.38, 0.42)
        crate.mesh = box
        crate.position = offset
        crate.rotation_degrees = Vector3(0.0, offset.x * 90.0, 0.0)
        crate.material_override = crate_material
        root.add_child(crate)


func _add_survey(root: Node3D) -> void:
    var leg_material := _material(Color(0.25, 0.25, 0.3), 0.8)
    for angle in [0.0, 120.0, 240.0]:
        var leg := MeshInstance3D.new()
        var mesh := CylinderMesh.new()
        mesh.top_radius = 0.025
        mesh.bottom_radius = 0.025
        mesh.height = 1.1
        leg.mesh = mesh
        leg.position = Vector3(0.0, 0.55, 0.0)
        leg.rotation_degrees = Vector3(18.0, 0.0, 0.0)
        var pivot := Node3D.new()
        pivot.rotation_degrees = Vector3(0.0, angle, 0.0)
        pivot.add_child(leg)
        root.add_child(pivot)
    var head := MeshInstance3D.new()
    var head_mesh := BoxMesh.new()
    head_mesh.size = Vector3(0.3, 0.2, 0.22)
    head.mesh = head_mesh
    head.position = Vector3(0.0, 1.15, 0.0)
    head.material_override = _material(Color(0.95, 0.62, 0.2))
    root.add_child(head)
    var core := MeshInstance3D.new()
    var core_mesh := CylinderMesh.new()
    core_mesh.top_radius = 0.08
    core_mesh.bottom_radius = 0.08
    core_mesh.height = 0.6
    core.mesh = core_mesh
    core.position = Vector3(0.35, 0.3, 0.3)
    core.rotation_degrees = Vector3(0.0, 0.0, 70.0)
    core.material_override = _material(Color(0.6, 0.45, 0.35))
    root.add_child(core)


func _add_ice(root: Node3D) -> void:
    var ice_material := _material(Color(0.78, 0.9, 1.0, 0.9), 0.2, 0.1)
    ice_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    for shard in [[Vector3(-0.15, 0.3, -0.1), 0.6, 15.0], [Vector3(0.2, 0.22, 0.12), 0.45, -20.0], [Vector3(0.0, 0.18, 0.3), 0.35, 40.0]]:
        var crystal := MeshInstance3D.new()
        var prism := PrismMesh.new()
        prism.size = Vector3(0.3, shard[1], 0.3)
        crystal.mesh = prism
        crystal.position = shard[0]
        crystal.rotation_degrees = Vector3(0.0, shard[2], 8.0)
        crystal.material_override = ice_material
        root.add_child(crystal)
    var dish := MeshInstance3D.new()
    var dish_mesh := CylinderMesh.new()
    dish_mesh.top_radius = 0.55
    dish_mesh.bottom_radius = 0.6
    dish_mesh.height = 0.05
    dish.mesh = dish_mesh
    dish.position = Vector3(0.0, 0.025, 0.0)
    dish.material_override = _material(Color(0.6, 0.72, 0.8))
    root.add_child(dish)


func _add_flag(root: Node3D, site_id: String) -> void:
    var pole_material := _material(Color(0.82, 0.82, 0.86))
    var pole := MeshInstance3D.new()
    var pole_mesh := CylinderMesh.new()
    pole_mesh.top_radius = 0.03
    pole_mesh.bottom_radius = 0.03
    pole_mesh.height = 2.2
    pole.mesh = pole_mesh
    pole.position = Vector3(0.38, 1.1, -0.38)
    pole.material_override = pole_material
    root.add_child(pole)
    var pennant := MeshInstance3D.new()
    var flag := BoxMesh.new()
    flag.size = Vector3(0.5, 0.3, 0.03)
    pennant.mesh = flag
    pennant.position = Vector3(0.65, 2.0, -0.38)
    var pennant_material := StandardMaterial3D.new()
    pennant_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    pennant_material.albedo_color = FREE
    pennant.material_override = pennant_material
    root.add_child(pennant)
    _pennants[site_id] = pennant_material
