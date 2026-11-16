extends SceneTree
const Session = preload("res://scripts/frontend/game_session.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("RADIATION_UI_FAIL ", message)

func frames() -> void:
	for i in 6: await process_frame

func run() -> void:
	Session.begin({}, 1, false)
	var main: Node = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	await frames()
	main.bridge.auto_advance = false
	var sim: RefCounted = main.bridge._backend
	var hud: Control = main._hud
	sim.enable_radiation()
	sim._state.radiation.next_tick = int(sim._state.records.clock.tick_index)
	hud._time(1)
	sim.process_pending_commands()
	sim.step(1.0)
	await frames()
	check(hud._skin.radiation_choices.visible, "warning choices are visible")
	check(hud._skin.mission_title.text == "Solar radiation alert", "solar warning has the right name")
	check(hud._state.alerts.any(func(a): return a.code == "radiation_event"), "event is included in real alerts")
	hud._skin.radiation_choices.get_child(0).pressed.emit()
	sim.process_pending_commands()
	await frames()
	check(sim.get_radiation_state().sheltering, "Shelter crew button commits the protection")
	check(not main._crew_view.visible, "sheltering astronauts are inside rather than shown working outdoors")
	hud._skin.radiation_choices.get_child(1).pressed.emit()
	sim.process_pending_commands()
	await frames()
	check(not sim.get_radiation_state().sheltering and main._crew_view.visible, "Continue working resumes the crew")
	main.queue_free()
	await frames()
	Session.reset()
	if failures == 0: print("RADIATION_UI_PASS checks=", checks)
	quit(0 if failures == 0 else 1)
