class_name PlacementController
extends Node3D
## Placement preview: cursor -> cell, ghost footprint coloured by validate_placement, R to rotate,
## left click to submit, Escape / right click to cancel. The preview is advisory: the controller
## only emits a place_building payload; whoever owns the simulation (bridge -> Task 01) decides.
## Input is handled in _unhandled_input so UI Controls take precedence.

signal preview_changed(result: Dictionary, request: Dictionary)
signal hover_cell_changed(cell: Array)
signal placement_submitted(payload: Dictionary)
signal placement_cancelled()
signal mode_changed(active: bool, definition_id: String)

const VALID := Color(0.25, 0.95, 0.45, 0.45)
const INVALID := Color(0.95, 0.25, 0.25, 0.45)
const ENTRANCE := Color(0.95, 0.95, 1.0, 0.6)
const CURSOR := Color(1.0, 1.0, 1.0, 0.25)

var world_service: RefCounted
var camera_rig: Node3D
var terrain: Node3D
var snapshot_provider: Callable  # -> Dictionary

var active: bool = false
var definition_id: String = ""
var rotation_quarters: int = 0
var hover_cell: Array = []
var last_result: Dictionary = {}

var _ghost: Node3D
var _cursor: MeshInstance3D
var _ghost_materials: Array = []
var _last_signature: String = ""


func setup(service: RefCounted, rig: Node3D, terrain_view: Node3D, provider: Callable) -> void:
    world_service = service
    camera_rig = rig
    terrain = terrain_view
    snapshot_provider = provider
    _cursor = MeshInstance3D.new()
    _cursor.name = "Cursor"
    var plate := BoxMesh.new()
    plate.size = Vector3(0.98, 0.03, 0.98)
    _cursor.mesh = plate
    _cursor.material_override = _ghost_material(CURSOR)
    _cursor.visible = false
    add_child(_cursor)
    _ghost = Node3D.new()
    _ghost.name = "Ghost"
    add_child(_ghost)


func begin_placement(id: String) -> bool:
    if world_service == null or not world_service.definitions.has(id):
        return false
    definition_id = id
    active = true
    _last_signature = ""
    mode_changed.emit(true, definition_id)
    _refresh()
    return true


func cancel_placement() -> void:
    if not active:
        return
    active = false
    definition_id = ""
    last_result = {}
    _clear_ghost()
    mode_changed.emit(false, "")
    placement_cancelled.emit()


func rotate_preview(steps: int = 1) -> void:
    rotation_quarters = posmod(rotation_quarters + steps, 4)
    _last_signature = ""
    _refresh()


func refresh_from_snapshot() -> void:
    ## Call after the snapshot changes so the ghost re-validates against new occupancy.
    _last_signature = ""
    _refresh()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion:
        _update_hover(event.position)
    elif event is InputEventMouseButton and event.pressed:
        if event.button_index == MOUSE_BUTTON_LEFT and active:
            _update_hover(event.position)
            if last_result.get("valid", false):
                placement_submitted.emit({"definition_id": definition_id, "cell": hover_cell.duplicate(), "rotation_quarters": rotation_quarters})
                get_viewport().set_input_as_handled()
    elif event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_R and active:
            rotate_preview(1 if not event.shift_pressed else -1)
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_ESCAPE and active:
            cancel_placement()
            get_viewport().set_input_as_handled()


func _update_hover(screen_pos: Vector2) -> void:
    if camera_rig == null:
        return
    var point: Variant = camera_rig.ground_point(screen_pos, 0.0)
    if point == null:
        return
    var cell := [int(floor(point.x)), int(floor(point.z))]
    if hover_cell.is_empty() or cell[0] != hover_cell[0] or cell[1] != hover_cell[1]:
        hover_cell = cell
        hover_cell_changed.emit(cell)
        _cursor.visible = world_service.map.in_bounds(cell)
        if _cursor.visible:
            _cursor.position = Vector3(cell[0] + 0.5, _height(cell) + 0.02, cell[1] + 0.5)
        _refresh()


func _refresh() -> void:
    if not active or hover_cell.is_empty():
        return
    var snapshot: Dictionary = snapshot_provider.call() if snapshot_provider.is_valid() else {}
    var request := {"definition_id": definition_id, "cell": hover_cell.duplicate(), "rotation_quarters": rotation_quarters}
    var signature := "%s|%d|%d|%d|%s" % [definition_id, hover_cell[0], hover_cell[1], rotation_quarters, str(snapshot.get("revision", -1))]
    if signature == _last_signature:
        return
    _last_signature = signature
    last_result = world_service.validate_placement(request, snapshot)
    _draw_ghost(request, last_result)
    preview_changed.emit(last_result, request)


func _draw_ghost(request: Dictionary, result: Dictionary) -> void:
    _clear_ghost()
    var definition: Dictionary = world_service.definitions.get_definition(definition_id)
    # Always draw the rotated footprint at the cursor, even when invalid (the service returns empty arrays then).
    var occupied: Array = result.occupied_cells if result.get("valid", false) else _rotated(definition.footprint_cells, request)
    var entrances: Array = result.entrance_cells if result.get("valid", false) else _rotated(definition.entrance_cells, request)
    var color := VALID if result.get("valid", false) else INVALID
    var height := float(definition.get("metadata", {}).get("visual", {}).get("height_m", 2.0))
    for cell in occupied:
        var block := MeshInstance3D.new()
        var box := BoxMesh.new()
        box.size = Vector3(0.96, height, 0.96)
        block.mesh = box
        block.position = Vector3(cell[0] + 0.5, _height(cell) + height * 0.5, cell[1] + 0.5)
        block.material_override = _ghost_material(color)
        _ghost.add_child(block)
    for cell in entrances:
        var pad := MeshInstance3D.new()
        var plate := BoxMesh.new()
        plate.size = Vector3(0.7, 0.05, 0.7)
        pad.mesh = plate
        pad.position = Vector3(cell[0] + 0.5, _height(cell) + 0.04, cell[1] + 0.5)
        pad.material_override = _ghost_material(ENTRANCE if result.get("valid", false) else INVALID)
        _ghost.add_child(pad)


func _rotated(offsets: Array, request: Dictionary) -> Array:
    var cells: Array = []
    for offset in offsets:
        var x := int(offset[0])
        var z := int(offset[1])
        for _i in posmod(int(request.rotation_quarters), 4):
            var next_x := -z
            z = x
            x = next_x
        cells.append([int(request.cell[0]) + x, int(request.cell[1]) + z])
    return cells


func _height(cell: Array) -> float:
    return terrain.surface_height(cell[0] + 0.5, cell[1] + 0.5) if terrain != null else 0.0


func _clear_ghost() -> void:
    if _ghost == null:
        return
    for child in _ghost.get_children():
        child.queue_free()


static func _ghost_material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = color
    material.no_depth_test = false
    return material
