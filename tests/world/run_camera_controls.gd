extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _run() -> void:
	var main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.bridge.auto_advance = false
	var rig = main.camera_rig
	var before_focus: Vector3 = rig._target_focus
	var yaw: float = rig._target_yaw
	var pitch: float = rig._target_pitch
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	rig._unhandled_input(middle)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(30, 20)
	rig._unhandled_input(motion)
	check(rig._target_yaw != yaw and rig._target_pitch != pitch, "middle drag rotates and tilts")
	check(rig._target_focus == before_focus, "middle drag does not pan")
	middle.pressed = false
	rig._input(middle)
	check(not rig._orbiting, "middle release over a panel ends orbit")
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	rig._unhandled_input(right)
	check(not rig._orbiting, "right button does not orbit")
	rig._target_focus = Vector3(8, 0, 8)
	rig._edge_pan(Vector2(1, 450), Vector2(1600, 900), 0.1)
	check(rig._target_focus != Vector3(8, 0, 8), "edge scrolling pans")
	before_focus = rig._target_focus
	rig._edge_pan(Vector2(800, 450), Vector2(1600, 900), 0.1)
	check(rig._target_focus == before_focus, "centre of viewport does not edge pan")
	rig._edge_pan(Vector2(-1, 450), Vector2(1600, 900), 0.1)
	check(rig._target_focus == before_focus, "pointer outside viewport does not edge pan")
	main.begin_placement("fixture_storage_module")
	check(main.placement.active, "placement starts")
	main.placement._unhandled_input(right)
	check(not main.placement.active, "right click cancels placement")
	for entry in [[KEY_1, 1], [KEY_2, 5], [KEY_3, 20]]:
		var key := InputEventKey.new()
		key.keycode = entry[0]
		key.pressed = true
		main._unhandled_input(key)
		check(main.bridge.get_snapshot().clock.time_scale == entry[1], "number key changes time instead of placing a module")
	main.free()
	for failure in failures: print("CAMERA_CONTROLS_FAIL ", failure)
	print("CAMERA_CONTROLS_RESULT checks=", checks, " failures=", failures.size())
	if failures.is_empty(): print("CAMERA_CONTROLS_PASS")
	quit(0 if failures.is_empty() else 1)
