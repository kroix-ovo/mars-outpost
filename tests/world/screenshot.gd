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
                _step = 1
                _frame = 0
        1:
            if _frame >= 10:
                _capture("world_02_preview_valid")
                var placement: Node3D = _main.get_node("Placement")
                placement.hover_cell = [7, 3]
                placement.call("_refresh")
                _step = 2
                _frame = 0
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
                _step = 3
                _frame = 0
        3:
            if _frame >= 10:
                _capture("world_04_constructing_and_status")
                var bridge: Node = _main.get_node("Integration")
                bridge._backend.advance(30.0)
                var rig: Node3D = _main.get_node("CameraRig")
                rig._target_distance = 14.0
                rig._target_yaw = -30.0
                rig._target_pitch = 40.0
                rig.focus_on(Vector3(6.0, 0.0, 5.0))
                _step = 4
                _frame = 0
        4:
            if _frame >= 45:
                _capture("world_05_commissioned_close")
                print("SCREENSHOTS_DONE")
                quit(0)
    return false


func _capture(name: String) -> void:
    var image := root.get_texture().get_image()
    var path := ProjectSettings.globalize_path(OUT_DIR + "/" + name + ".png")
    var err := image.save_png(path)
    print("captured ", path, " err=", err)
