extends SceneTree
## Bounded main-thread timing probe; includes production HUD/world snapshot work,
## excludes GPU rendering and does not claim a measured display frame rate.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main = load("res://scenes/world/main.tscn").instantiate()
	root.add_child(main)
	main.load_world(1)
	main.bridge.set_process(false)
	main._hud._tour.skip()
	main.bridge.set_time_scale(20)
	for i in 4: await process_frame
	var sample_count := 180 if "--sustained" in OS.get_cmdline_user_args() else 12
	for delta in [1.0 / 60.0, 1.0 / 7.0]:
		var samples: Array[float] = []
		var start_tick: int = main.bridge.get_snapshot().clock.tick_index
		var frame_start := Time.get_ticks_usec()
		for i in sample_count:
			var start := Time.get_ticks_usec()
			main.bridge._process(delta)
			samples.append((Time.get_ticks_usec() - start) / 1000.0)
			await process_frame
		var frame_ms := (Time.get_ticks_usec() - frame_start) / (1000.0 * sample_count)
		var total := 0.0
		for value in samples: total += value
		samples.sort()
		print("PACING_PROFILE delta=", delta, " mean_update_ms=", total / samples.size(),
			" max_update_ms=", samples[-1], " simulated_seconds=", main.bridge.get_snapshot().clock.tick_index - start_tick)
		print("PACING_FRAMES mean_ms=", frame_ms, " display=", DisplayServer.get_name())
	var state: Dictionary = main.bridge.get_snapshot()
	for entry in [["world", Callable(main, "_on_snapshot")], ["hud", Callable(main._hud, "_on_snapshot")]]:
		var start := Time.get_ticks_usec()
		for i in 12: entry[1].call(state)
		print("PACING_VIEW ", entry[0], " mean_ms=", (Time.get_ticks_usec() - start) / 12000.0)
	main.bridge._backend.set_block_signals(true)
	var backend_start := Time.get_ticks_usec()
	var tick_before: int = main.bridge._backend.get_snapshot().clock.tick_index
	main.bridge._backend.advance(1.0)
	print("PACING_BACKEND ticks=", main.bridge._backend.get_snapshot().clock.tick_index - tick_before,
		" total_ms=", (Time.get_ticks_usec() - backend_start) / 1000.0)
	main.free()
	quit()
