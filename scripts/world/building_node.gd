class_name BuildingNode
extends Node3D
## One placed building. Uses authored art when the scene provides an "Art" child (or any child
## present before the first apply_record), otherwise builds a procedural placeholder from the
## footprint and metadata.visual hints. Applies snapshot state: lifecycle (constructing /
## commissioned / destroyed), enabled, condition, power served vs requested and blocking codes.
## Reads only; never writes simulation state.
##
## Authored art convention: model the building with the anchor cell's centre at the origin,
## +X and +Z pointing to the next footprint cells, Y up. The node rotates the art for
## rotation_quarters (contract rule (x, z) -> (-z, x) is a -90 degree turn about Y per quarter).
##
## Status is shown with colour AND shape (colour-blind safe): sphere = operating, cube = warning,
## triangle = failure, flat disc = off / under construction.

const STATUS_OK := Color(0.30, 0.90, 0.40)
const STATUS_WARN := Color(1.00, 0.72, 0.15)
const STATUS_FAIL := Color(0.95, 0.20, 0.20)
const STATUS_OFF := Color(0.60, 0.60, 0.66)
const SCAFFOLD := Color(0.95, 0.80, 0.30)
const HOVER := Color(0.92, 0.94, 0.96, 0.75)
const SELECTED := Color(1.00, 0.68, 0.22, 0.95)
const ModuleArtScript := preload("res://scripts/world/module_art.gd")

enum StatusKind { OK, WARN, FAIL, OFF }

var definition_id: String = ""
var definition: Dictionary = {}
var ground_height: float = 0.0
var record: Dictionary = {}
var occupied_cells: Array = []
var entrance_cells: Array = []
var status_kind: int = StatusKind.OFF

var _body: Node3D
var _scaffold: Node3D
var _entrances: Node3D
var _light: MeshInstance3D
var _materials: Array = []  # [{material: StandardMaterial3D, base: Color}]
var _authored: Array = []  # Node3D children supplied by an authored scene
var _base_color: Color = Color(0.75, 0.75, 0.78)
var _built_for: String = ""
var _light_kind: int = -1
var _highlight: Node3D
var _label: Label3D
var _highlight_mode: int = 0  # 0 none, 1 hover, 2 selected


func apply_record(new_record: Dictionary, cells: Dictionary) -> void:
    record = new_record
    occupied_cells = cells.get("occupied_cells", [])
    entrance_cells = cells.get("entrance_cells", [])
    var signature := "%s|%d|%d|%d" % [definition_id, int(record.cell[0]), int(record.cell[1]), int(record.rotation_quarters)]
    if signature != _built_for:
        _rebuild()
        _built_for = signature
    _apply_status()
    if _highlight_mode != 0 and _label != null:
        _label.text = _label_text()


func status_color() -> Color:
    return _light.material_override.albedo_color if _light != null else STATUS_OFF


func status_summary() -> String:
    ## Human readable state for the debug overlay / tooltips.
    var codes: Array = record.get("blocking_codes", [])
    var text := "%s  [%s]" % [definition.get("display_name", definition_id), record.get("lifecycle", "?")]
    if record.get("lifecycle") == "constructing":
        text += "  %d%%" % int(round(float(record.get("construction_progress", 0.0)) * 100.0))
    text += "  cond %.0f%%" % (float(record.get("condition", 1.0)) * 100.0)
    if float(record.get("power_requested_kw", 0.0)) > 0.0:
        text += "  power %.1f/%.1f kW" % [float(record.get("power_served_kw", 0.0)), float(record.get("power_requested_kw", 0.0))]
    if not codes.is_empty():
        text += "  blocked: " + ", ".join(codes)
    return text


# ---------------------------------------------------------------- build

func _rebuild() -> void:
    if _authored.is_empty() and _body == null:
        for child in get_children():
            if child is Node3D:
                _authored.append(child)
        # Definitions without a scene (synthetic training content) use the shared module models.
        if _authored.is_empty() and ModuleArtScript.kind_for(definition) != "generic":
            var art: Node3D = ModuleArtScript.new()
            art.name = "Art"
            art.kind = ModuleArtScript.kind_for(definition)
            art.footprint = definition.get("footprint_cells", [[0, 0]])
            art.entrances = definition.get("entrance_cells", [])
            add_child(art)
            _authored.append(art)
    for child in [_scaffold, _entrances, _light, _highlight, _label]:
        if child != null:
            child.queue_free()
    if _body != null:
        for art in _authored:
            if art.get_parent() == _body:
                _body.remove_child(art)
        _body.queue_free()
    _materials.clear()
    var visual: Dictionary = definition.get("metadata", {}).get("visual", {})
    _base_color = Color.from_string(str(visual.get("color", "#bfbfc4")), Color(0.75, 0.75, 0.78))
    var height := float(visual.get("height_m", 2.0))
    for art in _authored:
        if "top_height" in art:
            height = float(art.top_height)
    var shape := str(visual.get("shape", "box"))
    var anchor := Vector3(float(record.cell[0]), ground_height, float(record.cell[1]))
    position = anchor
    var quarters := int(record.get("rotation_quarters", 0))

    _body = Node3D.new()
    _body.name = "Body"
    add_child(_body)
    if _authored.is_empty():
        for cell in occupied_cells:
            var local := Vector3(float(cell[0]) - anchor.x + 0.5, 0.0, float(cell[1]) - anchor.z + 0.5)
            _body.add_child(_placeholder_mesh(shape, height, local))
    else:
        for art in _authored:
            if art.get_parent() != null:
                art.get_parent().remove_child(art)
            _body.add_child(art)
            art.position = Vector3(0.5, 0.0, 0.5)
            art.rotation = Vector3(0.0, -quarters * PI * 0.5, 0.0)
            _collect_materials(art)
    _scaffold = Node3D.new()
    _scaffold.name = "Scaffold"
    add_child(_scaffold)
    for cell in occupied_cells:
        var local := Vector3(float(cell[0]) - anchor.x + 0.5, 0.0, float(cell[1]) - anchor.z + 0.5)
        _scaffold.add_child(_scaffold_mesh(height, local))
    _entrances = Node3D.new()
    _entrances.name = "Entrances"
    add_child(_entrances)
    for cell in entrance_cells:
        var local := Vector3(float(cell[0]) - anchor.x + 0.5, 0.03, float(cell[1]) - anchor.z + 0.5)
        _entrances.add_child(_entrance_pad(local))
    _light = MeshInstance3D.new()
    _light.name = "StatusLight"
    var centre := _footprint_centre(anchor)
    _light.position = Vector3(centre.x, height + 0.3, centre.z)
    var light_material := StandardMaterial3D.new()
    light_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    light_material.albedo_color = STATUS_OFF
    _light.material_override = light_material
    _light_kind = -1
    add_child(_light)
    _build_highlight(anchor, height)


func _collect_materials(node: Node) -> void:
    ## Gives every authored mesh its own material copy so tints never leak between instances.
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        var source: Material = mesh_instance.material_override
        if source == null and mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
            source = mesh_instance.mesh.surface_get_material(0)
        if source is StandardMaterial3D:
            var copy: StandardMaterial3D = source.duplicate()
            mesh_instance.material_override = copy
            _materials.append({"material": copy, "base": copy.albedo_color,
                "emission": float(source.get_meta("indicator", 0.0))})
    for child in node.get_children():
        _collect_materials(child)


func _footprint_centre(anchor: Vector3) -> Vector3:
    if occupied_cells.is_empty():
        return Vector3(0.5, 0.0, 0.5)
    var total := Vector3.ZERO
    for cell in occupied_cells:
        total += Vector3(float(cell[0]) - anchor.x + 0.5, 0.0, float(cell[1]) - anchor.z + 0.5)
    return total / occupied_cells.size()


func _placeholder_mesh(shape: String, height: float, local: Vector3) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    var material := StandardMaterial3D.new()
    material.albedo_color = _base_color
    material.roughness = 0.75
    material.metallic = 0.15
    _materials.append({"material": material, "base": _base_color})
    match shape:
        "tank":
            var cylinder := CylinderMesh.new()
            cylinder.top_radius = 0.42
            cylinder.bottom_radius = 0.42
            cylinder.height = height
            instance.mesh = cylinder
            instance.position = local + Vector3(0.0, height * 0.5, 0.0)
        "dome":
            var dome := SphereMesh.new()
            dome.radius = 0.5
            dome.height = height * 0.9
            dome.is_hemisphere = true
            instance.mesh = dome
            instance.position = local + Vector3(0.0, height * 0.1, 0.0)
            instance.scale = Vector3(0.96, 1.0, 0.96)
        "panel":
            var panel := BoxMesh.new()
            panel.size = Vector3(0.94, 0.06, 0.94)
            instance.mesh = panel
            instance.position = local + Vector3(0.0, height, 0.0)
            instance.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
            var post := MeshInstance3D.new()
            var post_mesh := CylinderMesh.new()
            post_mesh.top_radius = 0.05
            post_mesh.bottom_radius = 0.05
            post_mesh.height = height
            post.mesh = post_mesh
            post.position = Vector3(0.0, -height * 0.5, 0.0)
            post.material_override = material
            instance.add_child(post)
        _:
            var box := BoxMesh.new()
            box.size = Vector3(0.92, height, 0.92)
            instance.mesh = box
            instance.position = local + Vector3(0.0, height * 0.5, 0.0)
    instance.material_override = material
    return instance


func _scaffold_mesh(height: float, local: Vector3) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(1.0, height + 0.2, 1.0)
    instance.mesh = box
    instance.position = local + Vector3(0.0, (height + 0.2) * 0.5, 0.0)
    var material := StandardMaterial3D.new()
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.albedo_color = Color(SCAFFOLD, 0.35)
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    instance.material_override = material
    return instance


func _entrance_pad(local: Vector3) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    var pad := BoxMesh.new()
    pad.size = Vector3(0.62, 0.03, 0.62)
    instance.mesh = pad
    instance.position = local
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.36, 0.34, 0.32)
    material.roughness = 0.9
    instance.material_override = material
    return instance


# ---------------------------------------------------------------- status

func _apply_status() -> void:
    var lifecycle := str(record.get("lifecycle", "commissioned"))
    var codes: Array = record.get("blocking_codes", [])
    var condition := clampf(float(record.get("condition", 1.0)), 0.0, 1.0)
    var progress := clampf(float(record.get("construction_progress", 1.0)), 0.0, 1.0)
    var constructing := lifecycle == "constructing"
    var destroyed := lifecycle == "destroyed"

    _scaffold.visible = constructing
    if constructing:
        _body.scale = Vector3(1.0, maxf(progress, 0.05), 1.0)
    elif destroyed:
        _body.scale = Vector3(1.05, 0.35, 1.05)
    else:
        _body.scale = Vector3.ONE

    for entry in _materials:
        var base: Color = entry.base
        var tint := base
        if constructing:
            tint = base.lerp(SCAFFOLD, 0.5)
        elif destroyed:
            tint = Color(0.18, 0.14, 0.12)
        else:
            tint = base.darkened((1.0 - condition) * 0.6)
            if not bool(record.get("enabled", true)):
                tint = tint.lerp(Color(0.5, 0.5, 0.55), 0.6)
        entry.material.albedo_color = tint
        if float(entry.get("emission", 0.0)) > 0.0:
            var live := not constructing and not destroyed and bool(record.get("enabled", true)) and condition > 0.0
            entry.material.emission_energy_multiplier = float(entry.emission) * (condition if live else 0.0)

    var kind := StatusKind.OK
    if destroyed or codes.has("no_power") or codes.has("damaged"):
        kind = StatusKind.FAIL
    elif constructing or codes.has("disabled"):
        kind = StatusKind.OFF
    elif not codes.is_empty() or condition < 0.5:
        kind = StatusKind.WARN
    status_kind = kind
    _set_light(kind)
    _light.visible = not destroyed


func _set_light(kind: int) -> void:
    var color := STATUS_OK
    match kind:
        StatusKind.WARN:
            color = STATUS_WARN
        StatusKind.FAIL:
            color = STATUS_FAIL
        StatusKind.OFF:
            color = STATUS_OFF
    _light.material_override.albedo_color = color
    if kind == _light_kind:
        return
    _light_kind = kind
    _light.rotation = Vector3.ZERO
    match kind:
        StatusKind.OK:
            var sphere := SphereMesh.new()
            sphere.radius = 0.12
            sphere.height = 0.24
            _light.mesh = sphere
        StatusKind.WARN:
            var cube := BoxMesh.new()
            cube.size = Vector3(0.22, 0.22, 0.22)
            _light.mesh = cube
            _light.rotation_degrees = Vector3(0.0, 45.0, 0.0)
        StatusKind.FAIL:
            var prism := PrismMesh.new()
            prism.size = Vector3(0.3, 0.28, 0.3)
            _light.mesh = prism
        _:
            var disc := CylinderMesh.new()
            disc.top_radius = 0.18
            disc.bottom_radius = 0.18
            disc.height = 0.06
            _light.mesh = disc


# ---------------------------------------------------------------- selection feedback

func set_highlight(mode: int) -> void:
    ## 0 none, 1 hover, 2 selected. Presentation only.
    _highlight_mode = mode
    if _highlight == null:
        return
    _highlight.visible = mode != 0
    _label.visible = mode != 0
    var color := SELECTED if mode == 2 else HOVER
    for child in _highlight.get_children():
        (child as MeshInstance3D).material_override.albedo_color = color
    _label.text = _label_text()


func _label_text() -> String:
    var text := str(definition.get("display_name", definition_id))
    var lifecycle := str(record.get("lifecycle", ""))
    if lifecycle == "constructing":
        text += "  ·  building %d%%" % int(round(float(record.get("construction_progress", 0.0)) * 100.0))
    elif float(record.get("condition", 1.0)) < 1.0:
        text += "  ·  condition %d%%" % int(round(float(record.get("condition", 1.0)) * 100.0))
    elif not bool(record.get("enabled", true)):
        text += "  ·  off"
    return text


func _build_highlight(anchor: Vector3, height: float) -> void:
    _highlight = Node3D.new()
    _highlight.name = "Highlight"
    add_child(_highlight)
    var keys := {}
    for cell in occupied_cells:
        keys["%d,%d" % [int(cell[0]), int(cell[1])]] = true
    # Outline only the outer edges of the footprint, so multi-cell modules read as one unit.
    for cell in occupied_cells:
        var x := float(cell[0]) - anchor.x
        var z := float(cell[1]) - anchor.z
        for edge in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
            if keys.has("%d,%d" % [int(cell[0]) + edge[0], int(cell[1]) + edge[1]]):
                continue
            var bar := MeshInstance3D.new()
            var box := BoxMesh.new()
            box.size = Vector3(1.04, 0.05, 0.07) if edge[0] == 0 else Vector3(0.07, 0.05, 1.04)
            bar.mesh = box
            bar.position = Vector3(x + 0.5 + edge[0] * 0.5, 0.05, z + 0.5 + edge[1] * 0.5)
            var material := StandardMaterial3D.new()
            material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            material.albedo_color = HOVER
            bar.material_override = material
            _highlight.add_child(bar)
    _label = Label3D.new()
    _label.name = "NameLabel"
    var centre := _footprint_centre(anchor)
    _label.position = Vector3(centre.x, height + 0.65, centre.z)
    _label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    _label.fixed_size = true
    _label.pixel_size = 0.001
    _label.font_size = 19
    _label.outline_size = 8
    _label.outline_modulate = Color(0.05, 0.05, 0.06, 0.9)
    _label.no_depth_test = true
    _label.render_priority = 2
    add_child(_label)
    set_highlight(_highlight_mode)
