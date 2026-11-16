extends SceneTree
## Submission slice: simulation-owned repair challenges with a real lockout, and a
## greenhouse that produces real food. Marker: REPAIR_FARM_PASS.
const Simulation = preload("res://scripts/simulation/simulation.gd")
const World = preload("res://scripts/world/world_service.gd")
const Adapter = preload("res://scripts/crew/crew_adapter.gd")
const Repair = preload("res://scripts/systems/repair_challenge.gd")
const CONFIG := "res://tests/world/fixtures/landing_plain_init.json"
var checks := 0
var failures: Array[String] = []
var seq := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("REPAIR_FARM_FAIL ", label)

func new_sim() -> RefCounted:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.scenario_path))
	var world: RefCounted = World.from_files(scenario.map_path, scenario.building_definition_paths).service
	var sim = Simulation.new()
	var result: Dictionary = sim.initialize(config, world, Adapter.new(world))
	check(result.ok, "reference colony initializes: " + str(result.get("reason", "")))
	return sim

func send(sim: RefCounted, type: String, payload: Dictionary) -> Dictionary:
	seq += 1
	var id := "t:%d" % seq
	var accepted: Dictionary = sim.submit_command({"contract_version": "2.0.0", "command_id": id, "type": type, "payload": payload})
	if not accepted.accepted: return {"success": false, "code": accepted.code, "accepted": false, "data": {}}
	sim.process_pending_commands()
	return sim._journal[id].result

func find(sim: RefCounted, definition: String) -> String:
	for id in sim.get_snapshot().buildings:
		if sim.get_snapshot().buildings[id].definition_id == definition: return id
	return ""

func best_engineer(sim: RefCounted, best: bool) -> String:
	var chosen := ""
	var crew: Dictionary = sim.get_snapshot().crew
	for id in crew:
		if chosen.is_empty() or (crew[id].skills.get("engineering", 0.0) > crew[chosen].skills.get("engineering", 0.0)) == best: chosen = id
	return chosen

func solve_circuit(sim: RefCounted, wrong_first: int) -> Dictionary:
	var session: Dictionary = sim.get_repair_state().session
	var last := {}
	for miss in wrong_first:
		var slot := 0
		while int(session.right_order[slot]) == 0: slot += 1
		last = send(sim, "repair_input", {"session_id": session.id, "action": "connect", "value": float(slot)})
		if sim.get_repair_state().session == null: return last
	for slot in int(session.stages):
		last = send(sim, "repair_input", {"session_id": session.id, "action": "connect", "value": float(int(session.right_order[slot]) * 10 + slot)})
	return last

func run() -> void:
	farm()
	circuit()
	alignment()
	print("REPAIR_FARM_RESULT checks=%d failures=%d" % [checks, failures.size()])
	if failures.is_empty(): print("REPAIR_FARM_PASS checks=", checks)
	quit(0 if failures.is_empty() else 1)

func farm() -> void:
	var sim = new_sim()
	check(sim.supports_building("greenhouse_mk1"), "greenhouse process is executable")
	var before: Dictionary = sim.get_snapshot()
	var placed := {}
	for cell in [[20, 28], [22, 16], [9, 20], [24, 24], [10, 12]]:
		placed = send(sim, "place_building", {"definition_id": "greenhouse_mk1", "cell": cell, "rotation_quarters": 0})
		if placed.success: break
	check(placed.success, "greenhouse placed through the real command: " + str(placed.get("reason", "")))
	if not placed.success: return
	check(sim.get_snapshot().resources.alloy.amount == before.resources.alloy.amount - 8, "build cost debited once by the ledger")
	var crew_id := best_engineer(sim, true)
	check(send(sim, "assign_task", {"task_id": placed.data.task_id, "crew_ids": [crew_id], "priority": 60}).success, "builder assigned")
	var commissioned := false
	for i in 1500:
		sim.step(1.0)
		if sim.get_snapshot().buildings[placed.data.building_id].lifecycle == "commissioned":
			commissioned = true
			break
	check(commissioned, "crew labor commissions the greenhouse")
	var start: Dictionary = sim.get_snapshot()
	for i in 200: sim.step(1.0)
	var end: Dictionary = sim.get_snapshot()
	var farm_building: Dictionary = end.buildings[placed.data.building_id]
	check(farm_building.operating_fraction > 0.0, "greenhouse operates on real power and inputs: fraction %.2f" % farm_building.operating_fraction)
	var crew_food := 0.0
	for id in sim._state.crew_demand.provided: crew_food += sim._state.crew_demand.provided[id].get("food_kcal", 0.0)
	var produced: float = end.resources.food_kcal.amount - start.resources.food_kcal.amount + crew_food * 200.0
	check(produced > 0.0 and absf(produced - 0.05 * farm_building.operating_fraction * 200.0) < 0.5, "food stock gains the farm's real yield (%.2f kcal in 200 s) on top of crew meals" % produced)
	# Specialist work: a botanist walks to the farm, tends it, and the harvest is paid once.
	var tend_id := ""
	for id in end.tasks:
		if end.tasks[id].kind == "farm" and end.tasks[id].status not in ["completed", "cancelled", "failed"]: tend_id = id
	check(not tend_id.is_empty() and end.tasks[tend_id].target_id == placed.data.building_id, "commissioning opens a tending job at the farm")
	var botanist := ""
	for id in end.crew:
		if end.crew[id].status == "idle" and (botanist.is_empty() or end.crew[id].skills.get("botany", 0.0) > end.crew[botanist].skills.get("botany", 0.0)): botanist = id
	check(sim._crew_adapter.recommended_crew(end.tasks[tend_id], end)[0] == botanist, "Suggest crew picks the best botanist for tending")
	check(send(sim, "assign_task", {"task_id": tend_id, "crew_ids": [botanist], "priority": 40}).success, "botanist assigned to tend the farm")
	sim.step(1.0)
	check(sim.get_snapshot().crew[botanist].status in ["travelling", "working"], "the botanist travels to the farm and works there")
	var harvest_events: Array = []
	sim.game_event.connect(func(event): if event.type == "farm_tended": harvest_events.append(event))
	var food_low := 0.0
	for i in 1200:
		food_low = sim.get_snapshot().resources.food_kcal.amount
		sim.step(1.0)
		if not harvest_events.is_empty(): break
	check(harvest_events.size() == 1 and harvest_events[0].data.harvest_kcal == 1500.0 and sim.get_snapshot().resources.food_kcal.amount > food_low + 1400.0, "tending completes with one 1,500 kcal harvest through the ledger")
	check(sim.get_snapshot().crew[botanist].status == "idle", "the botanist is released afterwards")
	var reopened := 0
	for id in sim.get_snapshot().tasks:
		if sim.get_snapshot().tasks[id].kind == "farm" and sim.get_snapshot().tasks[id].status == "queued": reopened += 1
	check(reopened == 1, "a new tending job opens for the next shift")
	check(sim.get_capabilities().farm_production and not sim.get_capabilities().agriculture, "farm production reported; full agriculture still false")
	# Once the arrival CO2 buffer is gone, fresh crew CO2 must reach the farm before
	# the scrubber disposes of it. This is a reachable state during a real playthrough.
	sim._state.records.resources.co2_kg.amount = 0.0
	for i in 6: sim.step(1.0)
	var sustained: Dictionary = sim.get_snapshot()
	check(float(sustained.buildings[placed.data.building_id].operating_fraction) > 0.0, "farm keeps operating on recycled crew CO2 after the starting buffer is empty")

func circuit() -> void:
	var sim = new_sim()
	var events: Array = []
	sim.game_event.connect(func(event): events.append(event))
	var battery := find(sim, "battery_bank_mk1")
	var expert := best_engineer(sim, true)
	var novice := best_engineer(sim, false)
	check(not send(sim, "start_repair_challenge", {"building_id": battery, "crew_id": expert}).success, "no challenge without a fault")
	check(send(sim, "trigger_fault_drill", {"building_id": battery}).success and sim.get_snapshot().buildings[battery].condition == Repair.DRILL_CONDITION, "controlled fault damages the component")
	check(not send(sim, "trigger_fault_drill", {"building_id": find(sim, "solar_array_mk1")}).success, "one unresolved fault at a time")
	check(sim.get_repair_state().faults[battery].kind == "circuit", "battery uses the circuit interaction")
	# Failure path with the least skilled astronaut.
	check(send(sim, "start_repair_challenge", {"building_id": battery, "crew_id": novice}).success, "novice opens the challenge")
	var hard: Dictionary = sim.get_repair_state().session
	sim.step(1.0)
	var tick: int = sim.get_snapshot().clock.tick_index
	sim.advance(5.0)
	check(sim.get_snapshot().clock.tick_index == tick and sim.step(1.0).ok and sim.get_snapshot().clock.tick_index == tick, "colony time is frozen while the challenge is open")
	var failed := solve_circuit(sim, int(hard.mistakes_allowed) + 1)
	check(failed.data.get("finished", false) and not failed.data.success and sim.get_snapshot().buildings[battery].condition == 0.0, "too many mistakes: component fully broken")
	var fault: Dictionary = sim.get_repair_state().faults[battery]
	check(fault.status == "locked" and fault.locked_until_tick == tick + 86400, "full one-day lockout recorded")
	var injury: Dictionary = sim.get_repair_state().injuries.get(novice, {})
	check(failed.data.get("injured_crew_id") == novice and sim.get_snapshot().crew[novice].status == "incapacitated" and injury.days >= 1 and injury.days <= 7 and injury.recover_tick == tick + injury.days * 86400, "botched rewiring injures the operator for a seeded 1 to 7 days")
	var job_id := ""
	for id in sim.get_snapshot().tasks:
		if sim.get_snapshot().tasks[id].kind == "repair" and sim.get_snapshot().tasks[id].status not in ["completed", "cancelled", "failed"]: job_id = id
	check(not job_id.is_empty() and not send(sim, "assign_task", {"task_id": job_id, "crew_ids": [novice], "priority": 50}).success, "the injured astronaut cannot be assigned work")
	var blocked := send(sim, "start_repair_challenge", {"building_id": battery, "crew_id": expert})
	check(not blocked.success and blocked.code == "repair_locked" and blocked.data.retry_tick == tick + 86400, "another astronaut cannot bypass the lock")
	check(not send(sim, "repair_input", {"session_id": hard.id, "action": "connect", "value": 0.0}).success, "closed session accepts no input")
	check(sim.get_snapshot().tasks.values().all(func(task): return task.target_id != battery), "no routine repair job bypasses the lock")
	sim._state.records.clock.tick_index = tick + 86399
	sim._state.records.clock.elapsed_s = float(tick + 86399)
	check(not send(sim, "start_repair_challenge", {"building_id": battery, "crew_id": expert}).success, "still locked one second early")
	sim._state.records.clock.tick_index = tick + 86400
	sim._state.records.clock.elapsed_s = float(tick + 86400)
	check(send(sim, "start_repair_challenge", {"building_id": battery, "crew_id": expert}).success, "retry allowed when the lockout ends")
	var easy: Dictionary = sim.get_repair_state().session
	check(int(easy.stages) <= int(hard.stages) and int(easy.mistakes_allowed) >= int(hard.mistakes_allowed) and float(easy.skill) > float(hard.skill), "engineering skill reduces stages and adds tolerance")
	var fixed := solve_circuit(sim, 1)
	check(fixed.data.get("success", false) and sim.get_snapshot().buildings[battery].condition == 1.0 and sim.get_repair_state().faults[battery].status == "resolved", "correct wiring restores the component")
	check(not send(sim, "start_repair_challenge", {"building_id": battery, "crew_id": expert}).success, "result is applied once")
	check(sim.get_snapshot().crew[novice].status == "incapacitated", "still injured before the episode ends")
	sim._state.records.clock.tick_index = int(injury.recover_tick)
	sim._state.records.clock.elapsed_s = float(injury.recover_tick)
	sim.step(1.0)
	check(sim.get_snapshot().crew[novice].status == "idle" and sim.get_snapshot().crew[novice].health == 1.0 and sim.get_repair_state().injuries.is_empty(), "the astronaut recovers after the episode and returns to duty")
	var kinds := {}
	for event in events: kinds[event.type] = kinds.get(event.type, 0) + 1
	check(kinds.get("repair_failed", 0) == 1 and kinds.get("repair_succeeded", 0) == 1 and kinds.get("fault_started", 0) == 1, "one event per outcome")
	check(not send(sim, "repair_input", {"session_id": "x", "action": "win", "value": 1.0}).get("accepted", true), "UI cannot send a success action")

func alignment() -> void:
	var sim = new_sim()
	var solar := find(sim, "solar_array_mk1")
	var expert := best_engineer(sim, true)
	check(send(sim, "trigger_fault_drill", {"building_id": solar}).success and sim.get_repair_state().faults[solar].kind == "alignment", "solar equipment uses the alignment interaction")
	check(send(sim, "start_repair_challenge", {"building_id": solar, "crew_id": expert}).success, "alignment challenge opens")
	var session: Dictionary = sim.get_repair_state().session
	var finished := {}
	for stage in int(session.stages):
		# Drive the indicator with bounded time inputs until it is inside the window.
		for i in 4000:
			var view: Dictionary = sim.get_repair_state().session
			if absf(Repair.indicator(view) - float(view.targets[stage])) <= float(view.tolerance) * 0.5: break
			send(sim, "repair_input", {"session_id": session.id, "action": "tick", "value": 0.02})
		finished = send(sim, "repair_input", {"session_id": session.id, "action": "lock", "value": 0.0})
	check(finished.data.get("success", false) and sim.get_snapshot().buildings[solar].condition == 1.0, "timed locks inside the window calibrate the tracker")
	# Abandoning (closing) is a failure, and oversized time inputs are clamped.
	var battery := find(sim, "battery_bank_mk1")
	send(sim, "trigger_fault_drill", {"building_id": battery})
	send(sim, "start_repair_challenge", {"building_id": battery, "crew_id": expert})
	var open: Dictionary = sim.get_repair_state().session
	send(sim, "repair_input", {"session_id": open.id, "action": "tick", "value": 500.0})
	check(sim.get_repair_state().session != null and sim.get_repair_state().session.elapsed_s <= 0.1 + 1e-9, "challenge time input is bounded")
	var abandoned := send(sim, "repair_input", {"session_id": open.id, "action": "abandon", "value": 0.0})
	check(abandoned.data.get("finished", false) and not abandoned.data.success and sim.get_repair_state().faults[battery].status == "locked", "closing the repair cannot avoid the failure rule")
