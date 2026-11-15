extends Node3D
## Main world scene controller (Task 02 owns this scene). Wires the simulation bridge to the
## terrain, buildings, utility lines, sites, routes, camera and placement preview, and offers the
## mount points Task 03 uses: $CrewRoot (Node3D) for crew scenes and $UIRoot (CanvasLayer) for
## the HUD. Task 03 can also listen to site_selected / building_selected and call
## begin_placement(definition_id) instead of using the developer keys.
##
## Developer overlay keys (until the Task 03 HUD lands):
##   1-9 pick a building to place, R rotate, Esc cancel, G grid, F1 overlay, Space pause/resume,
##   +/- time scale, F2/F3 switch world preset, K/L force no_power/clear on hovered building (stub).

signal site_selected(site_id: String, route: Dictionary)
signal building_selected(building_id: String)
signal world_loaded(preset_name: String)

const WORLDS := [
    {
        "name": "fixture_flat_16",
        "map": "res://tests/simulation/fixtures/definitions/map/fixture_flat_16.json",
        "definitions": "res://tests/simulation/fixtures/definitions/buildings",
        "snapshot": "res://tests/simulation/fixtures/snapshots/salvage_6crew_tick0.json",
        "backend": 0,  # AUTO: Task 01's facade when present, else the fixture stub
        "config": "res://tests/simulation/fixtures/init/salvage_6crew.json",
    },
    {
        "name": "landing_plain",
        "map": "res://data/maps/landing_plain.json",
        "definitions": "res://data/buildings",
        "snapshot": "res://tests/world/fixtures/landing_plain_demo_snapshot.json",
        "backend": 0,
        "config": "res://tests/world/fixtures/landing_plain_init.json",
    },
]

@onready var bridge: Node = $Integration
@onready var terrain: Node3D = $Terrain
@onready var camera_rig: Node3D = $CameraRig
@onready var buildings: Node3D = $Buildings
@onready var utilities: Node3D = $Utilities
@onready var sites: Node3D = $Sites
@onready var routes: Node3D = $Routes
@onready var placement: Node3D = $Placement
@onready var lander: Node3D = $LandingShip
@onready var overlay: Label = $DevOverlay/Panel/Label
@onready var overlay_layer: CanvasLayer = $DevOverlay

var world_index: int = 0
var selected_site: String = ""
var selected_building: String = ""

var _hover_cell: Array = []
var _hover_site: String = ""
var _hover_route: Dictionary = {}
var _preview: Dictionary = {}
var _last_message: String = ""
var _events: Array = []
var _switching_world: bool = false
var _hud: Control
var _crew_view: Node3D


func _ready() -> void:
    if not bridge.is_ready():
        overlay.text = "World failed to boot. See the output log."
        return
    bridge.snapshot_changed.connect(_on_snapshot)
    bridge.command_resolved.connect(_on_command_resolved)
    bridge.game_event.connect(_on_game_event)
    bridge.simulation_failed.connect(_on_simulation_failed)
    placement.setup(bridge.world_service, camera_rig, terrain, Callable(bridge, "get_snapshot"))
    placement.placement_submitted.connect(_on_placement_submitted)
    placement.preview_changed.connect(_on_preview)
    placement.hover_cell_changed.connect(_on_hover_cell)
    placement.mode_changed.connect(func(active: bool, _id: String) -> void:
        terrain.set_grid_emphasis(active)
        _refresh_overlay())
    _crew_view = preload("res://scripts/crew/crew_view.gd").new()
    $CrewRoot.add_child(_crew_view)
    _hud = preload("res://scenes/ui/outpost_hud.tscn").instantiate()
    $UIRoot.add_child(_hud)
    _hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    # The camera keeps the colony centred in the world area between the roster and the drawer.
    _hud.layout_changed.connect(func(left_px: float, right_px: float) -> void:
        camera_rig.hud_width = right_px - left_px)
    _hud.reference_requested.connect(func(): load_world(1))
    _hud.refresh_layout()
    _crew_view.crew_selected.connect(_hud.select_crew)
    _hud.crew_selection_changed.connect(_crew_view.set_selected_crew)
    _hud.placement_requested.connect(func(definition_id: String, quarters: int) -> void:
        placement.rotation_quarters = quarters
        placement.begin_placement(definition_id))
    building_selected.connect(_hud.select_building)
    site_selected.connect(func(site_id: String, _route: Dictionary) -> void: _hud.select_site(site_id))
    get_viewport().physics_object_picking = true
    overlay_layer.visible = false
    _bind_world()


func load_world(index: int) -> Dictionary:
    ## Switches map, definitions and fixture snapshot. Everything rendered is rebuilt from the
    ## new snapshot; nothing carries over.
    if index < 0 or index >= WORLDS.size():
        return {"ok": false, "code": "invalid_value", "reason": "No such world preset."}
    var preset: Dictionary = WORLDS[index]
    _switching_world = true
    var result: Dictionary = bridge.load_world(preset.map, preset.definitions, preset.snapshot, int(preset.backend), preset.config)
    _switching_world = false
    if not result.ok:
        _last_message = "World load failed: %s (%s)" % [result.reason, result.code]
        _refresh_overlay()
        return result
    world_index = index
    bridge.auto_advance = true
    _last_message = "Loaded %s; colony restarted." % preset.name
    placement.cancel_placement()
    placement.setup(bridge.world_service, camera_rig, terrain, Callable(bridge, "get_snapshot"))
    _bind_world()
    world_loaded.emit(preset.name)
    return result


func begin_placement(definition_id: String) -> bool:
    return placement.begin_placement(definition_id)


func _bind_world() -> void:
    var map_data: RefCounted = bridge.map_data
    terrain.build(map_data)
    camera_rig.set_map_bounds(map_data.size_cells(), map_data.base_airlock_cell)
    buildings.reset()
    buildings.setup(bridge.world_service, terrain)
    utilities.reset()
    utilities.setup(bridge.world_service, terrain)
    sites.reset()
    sites.setup(terrain)
    routes.reset()
    selected_site = ""
    selected_building = ""
    _hover_site = ""
    _hover_route = {}
    _events.clear()
    _place_lander(map_data)
    if _hud != null:
        var catalog := {}
        for id in bridge.definitions.ids(): catalog[id] = bridge.definitions.get_definition(id)
        _hud.bind(bridge._backend, bridge.crew_adapter, bridge.world_service, catalog)
        _crew_view.apply_snapshot(bridge.get_snapshot(), true)
    _on_snapshot(bridge.get_snapshot())
    _frame_colony(map_data)


func _frame_colony(map_data: RefCounted) -> void:
    ## Start close enough to read the colony: frame the lander, airlock and existing modules.
    var airlock: Array = map_data.base_airlock_cell
    var lo := Vector2(float(airlock[0]) - 3.0, float(airlock[1]) - 2.0)
    var hi := Vector2(float(airlock[0]) + 1.0, float(airlock[1]) + 3.0)
    var snapshot: Dictionary = bridge.get_snapshot()
    for record in snapshot.get("buildings", {}).values():
        for cell in bridge.world_service.building_cells(record).occupied_cells:
            lo = Vector2(minf(lo.x, cell[0]), minf(lo.y, cell[1]))
            hi = Vector2(maxf(hi.x, cell[0] + 1.0), maxf(hi.y, cell[1] + 1.0))
    var centre := (lo + hi) * 0.5
    camera_rig.frame_area(Vector3(centre.x, 0.0, centre.y), (hi - lo).length() * 0.5)


func _on_snapshot(snapshot: Dictionary) -> void:
    if _switching_world: return # Rebind all views before consuming the new world's records.
    buildings.apply_snapshot(snapshot)
    utilities.apply_snapshot(snapshot)
    sites.apply_snapshot(snapshot)
    routes.apply_snapshot(snapshot)
    if _crew_view != null: _crew_view.apply_snapshot(snapshot)
    placement.refresh_from_snapshot()
    if selected_site != "":
        _preview_site_route(selected_site)
    _refresh_overlay()


func _on_hover_cell(cell: Array) -> void:
    _hover_cell = cell
    buildings.set_highlight(buildings.building_at_cell(cell) if not placement.active and cell.size() == 2 else "", selected_building)
    if _hud != null and cell.size() == 2: _hud.set_placement_cell(Vector2i(cell[0], cell[1]))
    var site_id: String = sites.site_at_cell(cell) if not placement.active else ""
    if site_id != _hover_site:
        _hover_site = site_id
        if selected_site == "":
            if site_id != "":
                _preview_site_route(site_id)
            else:
                routes.clear_preview()
                _hover_route = {}
    _refresh_overlay()


func _preview_site_route(site_id: String) -> void:
    var cell: Array = sites.site_cell(site_id)
    if cell.is_empty():
        routes.clear_preview()
        return
    _hover_route = bridge.query_route(bridge.map_data.base_airlock_cell, cell)
    routes.show_preview(_hover_route, cell, terrain.surface_height(cell[0] + 0.5, cell[1] + 0.5))


func _on_preview(result: Dictionary, request: Dictionary) -> void:
    _preview = result
    if _hud != null: _hud.set_placement_rotation(int(request.get("rotation_quarters", 0)))
    _refresh_overlay()


func _on_placement_submitted(payload: Dictionary) -> void:
    _last_message = "Submitting placement..."
    var response: Dictionary = bridge.submit_place_building(payload)
    if not response.accepted:
        _last_message = "Rejected: %s (%s)" % [response.reason, response.code]
    else:
        # submit_command resolves synchronously. Keep the emitted success/failure
        # message instead of overwriting it with an obsolete queued status.
        if _last_message == "Submitting placement...": _last_message = "Submitted %s" % response.command_id
    _refresh_overlay()


func _on_command_resolved(command_id: String, success: bool, reason: String) -> void:
    _last_message = "%s -> %s%s" % [command_id, "ok" if success else "failed", "" if reason.is_empty() else (": " + reason)]
    _refresh_overlay()


func _on_game_event(event: Dictionary) -> void:
    _events.append("%s %s %s" % [str(event.get("id", "")), str(event.get("type", "")), ", ".join(event.get("entity_ids", []))])
    if _events.size() > 5:
        _events.pop_front()
    _refresh_overlay()


func _on_simulation_failed(result: Dictionary) -> void:
    _last_message = "Simulation stopped: %s (%s). F2/F3 restarts the colony." % [result.reason, result.code]
    _refresh_overlay()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        # Clicking the world returns keyboard focus to the camera and time controls.
        get_viewport().gui_release_focus()
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not placement.active:
        _select_at(_hover_cell)
        return
    if not (event is InputEventKey and event.pressed and not event.echo):
        return
    var key := event as InputEventKey
    var ids: Array = bridge.definitions.ids()
    if key.keycode >= KEY_1 and key.keycode <= KEY_9:
        var index := key.keycode - KEY_1
        if index < ids.size():
            placement.begin_placement(ids[index])
            get_viewport().set_input_as_handled()
    elif key.keycode == KEY_G:
        terrain.set_grid_visible(not terrain.is_grid_visible())
    elif key.keycode == KEY_F1:
        overlay_layer.visible = not overlay_layer.visible
    elif key.keycode == KEY_F2:
        load_world(0)
    elif key.keycode == KEY_F3:
        load_world(1)
    elif key.keycode == KEY_SPACE:
        var scale := int(bridge.get_snapshot().get("clock", {}).get("time_scale", 1))
        bridge.set_time_scale(0 if scale != 0 else 1)
    elif key.keycode == KEY_EQUAL or key.keycode == KEY_KP_ADD:
        bridge.set_time_scale(_next_scale(1))
    elif key.keycode == KEY_MINUS or key.keycode == KEY_KP_SUBTRACT:
        bridge.set_time_scale(_next_scale(-1))
    elif key.keycode == KEY_T and selected_building != "":
        var selected: Dictionary = bridge.get_snapshot().buildings.get(selected_building, {})
        if not selected.is_empty():
            bridge.submit_command("set_building_enabled", {"building_id": selected_building, "enabled": not selected.enabled})
    elif key.keycode == KEY_K or key.keycode == KEY_L:
        var building_id: String = buildings.building_at_cell(_hover_cell) if not _hover_cell.is_empty() else ""
        if building_id != "":
            var patch := {"blocking_codes": ["no_power"], "power_requested_kw": 1.0, "power_served_kw": 0.0} if key.keycode == KEY_K else {"blocking_codes": [], "power_served_kw": 1.0}
            var result: Dictionary = bridge.dev_patch_building(building_id, patch)
            _last_message = "dev patch %s: %s" % [building_id, result.code]
            _refresh_overlay()


func _select_at(cell: Array) -> void:
    if cell.is_empty():
        return
    var site_id: String = sites.site_at_cell(cell)
    var building_id: String = buildings.building_at_cell(cell)
    selected_site = site_id
    selected_building = building_id
    buildings.set_highlight(building_id, building_id)
    if site_id != "":
        _preview_site_route(site_id)
        site_selected.emit(site_id, _hover_route.duplicate(true))
        _last_message = "Selected %s" % site_id
    elif building_id != "":
        routes.clear_preview()
        building_selected.emit(building_id)
        _last_message = "Selected %s" % building_id
    else:
        routes.clear_preview()
        _hover_route = {}
    _refresh_overlay()


func _next_scale(direction: int) -> int:
    var scales := [0, 1, 5, 20]
    var current := int(bridge.get_snapshot().get("clock", {}).get("time_scale", 1))
    var index := clampi(scales.find(current) + direction, 0, scales.size() - 1)
    return scales[index]


func _place_lander(map_data: RefCounted) -> void:
    ## The pre-landed habitat/lander sits one cell behind (-X of) the airlock cell. Visual only;
    ## on authored maps its cells are marked impassable in the map data.
    var airlock: Array = map_data.base_airlock_cell
    var x := float(airlock[0]) - 1.5
    var z := float(airlock[1]) + 0.5
    lander.position = Vector3(x, terrain.surface_height(x, z), z)


func _refresh_overlay() -> void:
    if not overlay_layer.visible:
        return
    var snapshot: Dictionary = bridge.get_snapshot()
    var clock: Dictionary = snapshot.get("clock", {})
    var lines: PackedStringArray = []
    lines.append("MARS OUTPOST  world harness   world: %s   backend: %s (%s)" % [WORLDS[world_index].name, bridge.backend_kind, bridge.backend_detail])
    lines.append("tick %d  elapsed %.0fs  x%d  revision %d  map %s" % [int(clock.get("tick_index", 0)), float(clock.get("elapsed_s", 0.0)), int(clock.get("time_scale", 1)), int(snapshot.get("revision", 0)), str(snapshot.get("map", {}).get("id", "?"))])
    lines.append("buildings %d  sites %d  expeditions %d  crew %d" % [snapshot.get("buildings", {}).size(), snapshot.get("sites", {}).size(), snapshot.get("expeditions", {}).size(), snapshot.get("crew", {}).size()])
    var power: Dictionary = snapshot.get("power", {})
    lines.append("POWER generated %.2f kW  load %.2f/%.2f kW  battery %.4f/%.2f kWh" % [power.get("generated_kw", 0.0), power.get("served_kw", 0.0), power.get("requested_kw", 0.0), power.get("battery_stored_kwh", 0.0), power.get("battery_capacity_kwh", 0.0)])
    if bridge.backend_kind == "simulation":
        lines.append("Life support + crew demand. Construction, crew jobs/EVA, health outcomes and saves are pending.")
        lines.append("Reference crew + game equipment assumptions." if world_index == 1 else "Synthetic fixture rates (not physiological values).")
    else:
        lines.append("VISUAL STUB: placement/construction are demonstrations; resources do not change.")
    var resources: Dictionary = snapshot.get("resources", {})
    for rid in ["oxygen_kg", "potable_water_kg", "co2_kg", "food_kcal"]:
        if not resources.has(rid): continue
        var r: Dictionary = resources[rid]
        var forecast = "  empty ~%.0f s at last rate" % r.forecast_empty_s if r.forecast_empty_s != null else ""
        lines.append("%s  %.4f  rate %+.6f/s%s" % [rid, r.amount, r.net_rate_per_s, forecast])
    for alert in snapshot.get("alerts", []): lines.append("WARNING %s: %s" % [alert.code, alert.message])
    var cut_off: Array = utilities.unreachable_buildings()
    if not cut_off.is_empty():
        lines.append("WARNING no reachable entrance: " + ", ".join(cut_off))
    lines.append("")
    if not _hover_cell.is_empty():
        var hover := "cell [%d, %d]" % [_hover_cell[0], _hover_cell[1]]
        var building_id: String = buildings.building_at_cell(_hover_cell)
        if building_id != "":
            hover += "  " + buildings.node_for(building_id).status_summary()
        var site_id: String = sites.site_at_cell(_hover_cell)
        if site_id != "":
            hover += "  " + sites.describe(site_id)
        lines.append(hover)
    var route_site := selected_site if selected_site != "" else _hover_site
    if route_site != "" and not _hover_route.is_empty():
        if _hover_route.reachable:
            lines.append("route airlock -> %s: %.0f m  (%s)" % [route_site, _hover_route.distance_m, _hover_route.route_id])
        else:
            lines.append("route airlock -> %s: UNREACHABLE (%s: %s)" % [route_site, _hover_route.code, _hover_route.reason])
    if placement.active:
        var state := "valid" if _preview.get("valid", false) else "blocked: %s" % _preview.get("reason", "")
        lines.append("placing %s  rot %d  -> %s" % [placement.definition_id, placement.rotation_quarters, state])
    else:
        var options: PackedStringArray = []
        var ids: Array = bridge.definitions.ids()
        for index in mini(ids.size(), 9):
            options.append("%d %s" % [index + 1, ids[index]])
        lines.append("place: " + "   ".join(options))
    lines.append("")
    lines.append("WASD/arrows or middle-drag pan  right-drag or Q/E orbit  wheel zoom  Home reset  click site/module to select")
    lines.append("R rotate  Esc cancel  G grid  Space pause  +/- speed  select module + T toggle  F1 hide  F2/F3 restart")
    if _last_message != "":
        lines.append("")
        lines.append(_last_message)
    for line in _events:
        lines.append("  event " + line)
    overlay.text = "\n".join(lines)
