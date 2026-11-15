extends SceneTree
## Captures screenshots of the world harness for handoff notes. Needs a real window (not
## --headless) because the Compatibility renderer must draw the frame.
## Run: Godot --path . --script tests/world/screenshot.gd
## Output: docs/screenshots/world_*.png

const OUT_DIR := "res://docs/screenshots"

var _main: Node3D
var _frame := 0
var _step := 0


func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    root.size = Vector2i(1600, 900)
    _main = load("res://scenes/world/main.tscn").instantiate()
    # The first five captures deliberately demonstrate visual construction, not
    # runtime construction (which remains unavailable). Never depend on AUTO.
    _main.get_node("Integration").backend = 1
    root.add_child(_main)


func _process(_delta: float) -> bool:
    _frame += 1
    match _step:
        0:
            if _frame >= 40:
                _capture("world_01_overview")
                var placement: Node3D = _main.get_node("Placement")
                placement.begin_placement("fixture_storage_module")
                placement.hover_cell = [7, 5]
                placement.hover_cell_changed.emit([7, 5])
                placement.call("_refresh")
                _next()
        1:
            if _frame >= 10:
                _capture("world_02_preview_valid")
                var placement: Node3D = _main.get_node("Placement")
                placement.hover_cell = [7, 3]
                placement.hover_cell_changed.emit([7, 3])
                placement.call("_refresh")
                _next()
        2:
            if _frame >= 10:
                _capture("world_03_preview_blocked")
                var placement: Node3D = _main.get_node("Placement")
                placement.cancel_placement()
                var bridge: Node = _main.get_node("Integration")
                bridge.submit_place_building({"definition_id": "fixture_storage_module", "cell": [7, 5], "rotation_quarters": 0})
                bridge.submit_place_building({"definition_id": "fixture_generator", "cell": [4, 6], "rotation_quarters": 1})
                bridge.dev_patch_building("building_000003", {"blocking_codes": ["no_power"], "power_requested_kw": 1.0, "power_served_kw": 0.0})
                bridge.dev_patch_building("building_000004", {"blocking_codes": ["input_limited:wastewater_kg"], "power_requested_kw": 1.0, "power_served_kw": 1.0})
                bridge.dev_patch_building("building_000005", {"lifecycle": "destroyed", "blocking_codes": ["destroyed"]})
                _next()
        3:
            if _frame >= 10:
                _capture("world_04_constructing_and_status")
                var bridge: Node = _main.get_node("Integration")
                bridge._backend.advance(30.0)
                _main.call("_on_hover_cell", [12, 8])
                var rig: Node3D = _main.get_node("CameraRig")
                rig._target_distance = 16.0
                rig._target_yaw = -30.0
                rig._target_pitch = 42.0
                rig.focus_on(Vector3(8.0, 0.0, 6.0))
                _next()
        4:
            if _frame >= 45:
                _capture("world_05_commissioned_route_preview")
                _main.load_world(1)
                _next()
        5:
            if _frame >= 45:
                _capture("world_06_landing_plain_overview")
                _main.call("_on_hover_cell", [15, 39])
                _main.call("_select_at", [15, 39])
                var rig: Node3D = _main.get_node("CameraRig")
                rig._target_distance = 22.0
                rig._target_yaw = 20.0
                rig._target_pitch = 48.0
                rig.focus_on(Vector3(15.0, 0.0, 26.0))
                _next()
        6:
            if _frame >= 45:
                _capture("world_07_landing_plain_modules_and_ice_route")
                var placement: Node3D = _main.get_node("Placement")
                placement.begin_placement("greenhouse_mk1")
                placement.hover_cell = [17, 29]
                placement.hover_cell_changed.emit([17, 29])
                placement.rotate_preview(1)
                _next()
        7:
            if _frame >= 10:
                _capture("world_08_landing_plain_rotated_preview")
                print("SCREENSHOTS_DONE")
                quit(0)
    return false


func _next() -> void:
    _step += 1
    _frame = 0


func _capture(name: String) -> void:
    var image := root.get_texture().get_image()
    var path := ProjectSettings.globalize_path(OUT_DIR + "/" + name + ".png")
    var err := image.save_png(path)
    print("captured ", path, " err=", err)
