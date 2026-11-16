extends SceneTree
const Harness = preload("res://tests/simulation/run_repair_farm.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("RADIATION_FAIL ", label)

func run() -> void:
	var harness = Harness.new()
	var exposed: RefCounted = harness.new_sim()
	var protected: RefCounted = harness.new_sim()
	check(exposed.enable_radiation().ok and protected.enable_radiation().ok, "opt-in succeeds")
	for sim in [exposed, protected]:
		sim._state.radiation.next_tick = 0
		sim.step(1.0)
		check(sim.get_radiation_state().status == "warning" and sim.get_snapshot().clock.time_scale == 0, "warning pauses once")
		check(harness.send(sim, "set_radiation_shelter", {"enabled":sim == protected}).success, "real response command")
		# Place the clock at the already scheduled event boundary; exercise real ticks.
		sim._state.records.clock.tick_index = int(sim._state.radiation.start_tick)
		sim._state.records.clock.elapsed_s = float(sim._state.records.clock.tick_index)
		sim.step(1.0)
		check(sim.get_radiation_state().status == "active", "event becomes active")
	for i in 100:
		exposed.step(1.0)
		protected.step(1.0)
	var unprotected_loss: float = 1.0 - exposed.get_snapshot().crew.crew_000001.health
	var sheltered_loss: float = 1.0 - protected.get_snapshot().crew.crew_000001.health
	check(unprotected_loss > 0, "radiation actually reduces health")
	check(absf(sheltered_loss * 10 - unprotected_loss) < 1e-8, "shelter reduces health loss by ninety percent")
	check(exposed.get_snapshot().crew.crew_000001.radiation_dose_msv == 0, "does not invent medical dose data")
	var clone: RefCounted = protected._state.clone()
	check(clone.radiation == protected._state.radiation, "event survives transactional cloning")
	# A sheltered construction assignment retains its task but earns no work.
	var placed: Dictionary = harness.send(protected, "place_building", {"definition_id":"greenhouse_mk1","cell":[20,28],"rotation_quarters":0})
	check(placed.success, "shelter test construction created")
	if placed.success:
		var assigned: Dictionary = harness.send(protected, "assign_task", {"task_id":placed.data.task_id,"crew_ids":["crew_000001"],"priority":60})
		check(assigned.success, "sheltered work remains assigned")
		var work_before: float = protected.get_snapshot().tasks[placed.data.task_id].completed_work_s
		for i in 10: protected.step(1.0)
		check(protected.get_snapshot().tasks[placed.data.task_id].completed_work_s == work_before, "sheltering pauses actual work progress")
	protected._state.records.clock.tick_index = int(protected._state.radiation.end_tick)
	protected._state.records.clock.elapsed_s = float(protected._state.records.clock.tick_index)
	protected.step(1.0)
	check(protected.get_radiation_state().status == "idle" and not protected.get_radiation_state().sheltering, "shelter lifts when the event clears")
	check(protected.get_capabilities().radiation_events, "capability reports the enabled mechanic")
	harness.free()
	if failures == 0: print("RADIATION_PASS checks=", checks)
	quit(0 if failures == 0 else 1)
