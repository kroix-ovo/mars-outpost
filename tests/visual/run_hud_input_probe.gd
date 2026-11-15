extends SceneTree
## Headless input-routing checks for the reworked mission control layout. Drives the real main
## scene with synthetic viewport input and verifies that panels do not trap or leak world input:
##  - a click on the world selects the module under the cursor and opens it in the Build drawer;
##  - clicks and wheel events over HUD panels never reach world selection or camera zoom;
##  - typing in a numeric field does not pan the camera or toggle pause;
##  - clicking the world releases keyboard focus back to camera/time controls;
##  - the camera starts framed on the colony and world switches rebind the HUD.
## Needs a real window: the headless display server has a 64x64 dummy viewport, so screen
## coordinates would not match the layout.
## Run: Godot --path . --resolution 1600x900 --script tests/visual/run_hud_input_probe.gd
## (also with --resolution 1280x720). Success marker: HUD_INPUT_PASS.

var _main: Node3D
var _hud: Control
var _rig: Node3D
var _frame := 0
var _step := 0
var _checks := 0
var _failures: Array[String] = []
var _saved: Dictionary = {}


func _initialize() -> void:
	_main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _step:
		0:
			if _frame >= 10:
				_hud = _main.get("_hud")
				_rig = _main.get_node("CameraRig")
				_check(_rig._target_distance <= 34.0, "camera starts framed on the colony (distance %.1f)" % _rig._target_distance)
				_hud._time(0)
				var id := _first_building()
				var screen := _screen_of_building(id)
				_check(_world_area().has_point(screen), "first module is visible in the open world area")
				_move(screen)
				_click(screen)
				_saved.id = id
				_next()
		1:
			if _frame >= 3:
				_check(_main.selected_building == _saved.id, "world click selects module under cursor")
				_check(_hud.selected_building_id() == _saved.id, "world selection shows in the Build drawer")
				_check(_hud._tabs.get_tab_title(_hud._tabs.current_tab) == "Build", "Build drawer opens for module selection")
				# A click on the drawer must not reach world selection.
				_main.selected_building = ""
				var drawer: Control = _hud.get_node("Drawer")
				var inside := drawer.get_global_rect().position + Vector2(drawer.size.x * 0.5, drawer.size.y - 14.0)
				_move(inside)
				_click(inside)
				_saved.distance = _rig._target_distance
				_wheel(inside)
				_next()
		2:
			if _frame >= 3:
				_check(_main.selected_building == "", "drawer click does not select world objects")
				_check(is_equal_approx(_rig._target_distance, _saved.distance), "wheel over drawer does not zoom the camera")
				var top: Control = _hud.get_node("StatusStrip")
				var strip := top.get_global_rect().position + Vector2(top.size.x * 0.6, top.size.y * 0.5)
				_wheel(strip)
				_check(is_equal_approx(_rig._target_distance, _saved.distance), "wheel over status strip does not zoom")
				_wheel(_world_area().get_center())
				_check(not is_equal_approx(_rig._target_distance, _saved.distance), "wheel over the world zooms")
				# Focus a numeric field, then press W and Space.
				_hud._open_tab("Build")
				var edit: LineEdit = _hud._x.get_line_edit()
				edit.grab_focus()
				_saved.focus = _rig._target_focus
				_saved.scale = int(_main.get_node("Integration").get_snapshot().clock.time_scale)
				_key(KEY_W, true)
				_key(KEY_SPACE, true)
				_next()
		3:
			if _frame >= 8:
				_key(KEY_W, false)
				_key(KEY_SPACE, false)
				_check(_rig._target_focus.is_equal_approx(_saved.focus), "typing W in a field does not pan the camera")
				_check(int(_main.get_node("Integration").get_snapshot().clock.time_scale) == _saved.scale, "typing Space in a field does not toggle pause")
				var world_point := _world_area().get_center() + Vector2(0, 120)
				_move(world_point)
				_click(world_point)
				_next()
		4:
			if _frame >= 3:
				_check(root.gui_get_focus_owner() == null, "clicking the world releases keyboard focus")
				_saved.focus = _rig._target_focus
				_key(KEY_W, true)
				_next()
		5:
			if _frame >= 8:
				_key(KEY_W, false)
				_check(not _rig._target_focus.is_equal_approx(_saved.focus), "W pans the camera when no field has focus")
				# Collapsing the drawer widens the world area and re-centres the camera offset.
				var before: float = _rig.hud_width
				_hud._toggle_drawer()
				_check(_rig.hud_width < before, "collapsed drawer frees world space for the camera")
				_hud._toggle_drawer()
				_main.load_world(1)
				_next()
		6:
			if _frame >= 10:
				var snapshot: Dictionary = _main.get_node("Integration").get_snapshot()
				_check(_hud._crew.item_count == snapshot.crew.size(), "HUD rebinds roster after world switch")
				_check(_hud._hud_title.text == "REFERENCE COLONY", "HUD labels the reference colony")
				_check(_rig._target_distance <= 34.0, "reference colony is framed on load")
				var id := _first_building()
				var screen := _screen_of_building(id)
				_move(screen)
				_click(screen)
				_next()
		7:
			if _frame >= 3:
				_check(_main.selected_building == _first_building(), "picking still maps to cells after the world switch")
				if _failures.is_empty():
					print("HUD_INPUT_PASS checks=", _checks)
					quit(0)
				else:
					for failure in _failures:
						print("HUD_INPUT_FAIL ", failure)
					quit(1)
	return false


func _next() -> void:
	_step += 1
	_frame = 0


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failures.append(label)


func _first_building() -> String:
	var ids: Array = _main.get_node("Integration").get_snapshot().buildings.keys()
	ids.sort()
	return ids[0]


func _screen_of_building(id: String) -> Vector2:
	var record: Dictionary = _main.get_node("Integration").get_snapshot().buildings[id]
	var camera: Camera3D = _rig.camera
	return camera.unproject_position(Vector3(record.cell[0] + 0.5, 0.0, record.cell[1] + 0.5))


func _world_area() -> Rect2:
	var crew: Control = _hud.get_node("CrewCard")
	var drawer: Control = _hud.get_node("Drawer")
	var top: Control = _hud.get_node("StatusStrip")
	var left := crew.get_global_rect().end.x
	var right := drawer.get_global_rect().position.x
	var y0 := top.get_global_rect().end.y
	return Rect2(left, y0, right - left, root.get_visible_rect().size.y - y0 - 60.0)


func _move(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = at
		button.global_position = at
		root.push_input(button, true)


func _wheel(at: Vector2) -> void:
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = at
	wheel.global_position = at
	root.push_input(wheel, true)


func _key(code: Key, pressed: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = pressed
	if pressed and code == KEY_W:
		key.unicode = "w".unicode_at(0)
	elif pressed and code == KEY_SPACE:
		key.unicode = 32
	Input.parse_input_event(key)
