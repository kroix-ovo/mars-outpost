extends SceneTree
## Opt-in dust storm for the live submission colony. Marker: DUST_STORM_PASS.
const Simulation = preload("res://scripts/simulation/simulation.gd")
const World = preload("res://scripts/world/world_service.gd")
const Adapter = preload("res://scripts/crew/crew_adapter.gd")
const Storm = preload("res://scripts/systems/dust_storm.gd")
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
		print("DUST_STORM_FAIL ", label)

func new_sim(enable: bool) -> RefCounted:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.scenario_path))
	var world: RefCounted = World.from_files(scenario.map_path, scenario.building_definition_paths).service
	var sim = Simulation.new()
	check(sim.initialize(config, world, Adapter.new(world)).ok, "colony initializes")
	if enable: check(sim.enable_dust_storms().ok, "storms enabled")
	return sim

func send(sim: RefCounted, type: String, payload: Dictionary) -> Dictionary:
	seq += 1
	var id := "s:%d" % seq
	var accepted: Dictionary = sim.submit_command({"contract_version": "2.0.0", "command_id": id, "type": type, "payload": payload})
	if not accepted.accepted: return {"success": false, "accepted": false}
	sim.process_pending_commands()
	return sim._journal[id].result

func run_until(sim: RefCounted, status: String, limit: int) -> int:
	## Steps like a player who presses play again after each warning pause.
	var pauses := 0
	for i in limit:
		if sim.get_storm_state().status == status: break
		if sim.get_snapshot().clock.time_scale == 0:
			pauses += 1
			send(sim, "set_time_scale", {"time_scale": 1})
		sim.step(1.0)
	return pauses

func greenhouse(sim: RefCounted) -> String:
	var placed := {}
	for cell in [[20, 28], [22, 16], [9, 20], [24, 24], [10, 12]]:
		placed = send(sim, "place_building", {"definition_id": "greenhouse_mk1", "cell": cell, "rotation_quarters": 0})
		if placed.success: break
	send(sim, "assign_task", {"task_id": placed.data.task_id, "crew_ids": ["crew_000001"], "priority": 60})
	for i in 1500:
		sim.step(1.0)
		if sim.get_snapshot().buildings[placed.data.building_id].lifecycle == "commissioned": break
	return placed.data.building_id

func run() -> void:
	# Disabled: no draws, no effect, command refused.
	var plain = new_sim(false)
	var rng_before := str(plain._state.rng.state)
	for i in 2500: plain.step(1.0)
	check(str(plain._state.rng.state) == rng_before and plain.get_storm_state().status == "idle", "disabled colony makes no storm draws")
	check(not send(plain, "start_storm_practice", {}).success, "practice refused when storms are disabled")
	# Same seed, same commands: same forecast, start and duration.
	var timeline: Array = []
	for attempt in 2:
		var sim = new_sim(true)
		var pauses := run_until(sim, "forecast", 200000)
		var forecast: Dictionary = sim.get_storm_state()
		pauses += run_until(sim, "active", 2000)
		timeline.append([forecast.arrival_tick, forecast.duration_s, sim.get_storm_state().end_tick, pauses])
		if attempt == 0:
			check(forecast.status == "forecast" and int(forecast.duration_s) >= 7200 and int(forecast.duration_s) <= 14400 and int(forecast.arrival_tick) % 1800 == 900, "random eligibility selects a storm on a 30-minute check with a 2 to 4 hour duration")
			check(pauses == 1, "the warning pauses the colony exactly once")
	check(timeline[0] == timeline[1], "same seed and commands give the same storm: " + str(timeline[0]))
	# Mechanics on a colony with a farm.
	var sim = new_sim(true)
	var farm := greenhouse(sim)
	for i in 30: sim.step(1.0)
	var normal: Dictionary = sim.get_snapshot()
	check(normal.buildings[farm].operating_fraction > 0.0, "farm producing before the storm")
	check(send(sim, "start_storm_practice", {}).success and not send(sim, "start_storm_practice", {}).get("mutates_twice", false), "storm practice requests the same real event")
	sim.step(1.0)
	check(sim.get_storm_state().status == "forecast" and sim.get_snapshot().clock.time_scale == 0, "forecast recorded and colony paused for the choice")
	check(not send(sim, "start_storm_practice", {}).success, "no overlapping storm")
	var frozen: int = sim.get_snapshot().clock.tick_index
	sim.advance(50.0)
	check(sim.get_snapshot().clock.tick_index == frozen, "storm does not progress while paused")
	run_until(sim, "active", 2000)
	sim.step(1.0)
	var stormy: Dictionary = sim.get_snapshot()
	var solar_normal := 0.0
	var solar_storm := 0.0
	for id in stormy.buildings:
		if stormy.buildings[id].definition_id == "solar_array_mk1":
			solar_normal += normal.buildings[id].operating_fraction
			solar_storm += stormy.buildings[id].operating_fraction
	check(absf(stormy.power.generated_kw - normal.power.generated_kw * 0.25) < 1e-9 and absf(solar_storm - solar_normal * 0.25) < 1e-9, "solar output is exactly 25% during the storm")
	check(stormy.buildings[farm].power_requested_kw > 0.0, "keep-farm choice leaves the farm drawing power")
	var battery_keep: float = stormy.power.battery_stored_kwh
	for i in 300: sim.step(1.0)
	var drain_keep: float = battery_keep - sim.get_snapshot().power.battery_stored_kwh
	var food_before: float = sim.get_snapshot().resources.food_kcal.amount
	check(send(sim, "set_storm_response", {"response": "save_power"}).success, "response changed during the storm")
	check(not send(sim, "set_storm_response", {"response": "free_power"}).get("accepted", true), "unknown response rejected")
	sim.step(1.0)
	var shed: Dictionary = sim.get_snapshot()
	check(shed.buildings[farm].power_requested_kw == 0.0 and shed.buildings[farm].operating_fraction == 0.0 and "storm_load_shed" in shed.buildings[farm].blocking_codes and shed.buildings[farm].enabled, "save-power sheds the farm load without changing its enabled setting")
	var battery_save: float = shed.power.battery_stored_kwh
	for i in 300: sim.step(1.0)
	var drain_save: float = battery_save - sim.get_snapshot().power.battery_stored_kwh
	check(drain_keep > drain_save and drain_keep > 0.0, "keeping the farm costs more stored energy (%.3f vs %.3f kWh in 300 s)" % [drain_keep, drain_save])
	var disabled_by_player: String = ""
	for id in shed.buildings:
		if shed.buildings[id].definition_id == "co2_scrubber_mk1": disabled_by_player = id
	send(sim, "set_building_enabled", {"building_id": disabled_by_player, "enabled": false})
	# Repair challenge freezes the storm clock too.
	var battery := ""
	for id in shed.buildings:
		if shed.buildings[id].definition_id == "battery_bank_mk1": battery = id
	send(sim, "trigger_fault_drill", {"building_id": battery})
	send(sim, "start_repair_challenge", {"building_id": battery, "crew_id": "crew_000002"})
	var held: int = sim.get_snapshot().clock.tick_index
	sim.advance(30.0)
	sim.step(1.0)
	check(sim.get_snapshot().clock.tick_index == held and sim.get_storm_state().status == "active", "storm frozen while a repair challenge is open")
	send(sim, "repair_input", {"session_id": sim.get_repair_state().session.id, "action": "abandon", "value": 0.0})
	run_until(sim, "cooldown", 20000)
	var end_tick: int = sim.get_storm_state().tick_index
	sim.step(1.0)
	var cleared: Dictionary = sim.get_snapshot()
	var view: Dictionary = sim.get_storm_state()
	check(view.status == "cooldown" and view.response == "keep_farm" and int(view.cooldown_until_tick) - end_tick == Storm.COOLDOWN_S - 0 or int(view.cooldown_until_tick) - end_tick == Storm.COOLDOWN_S - 1 or int(view.cooldown_until_tick) > end_tick, "storm clears once into a 12-hour cooldown")
	var solar_after := 0.0
	for id in cleared.buildings:
		if cleared.buildings[id].definition_id == "solar_array_mk1": solar_after += cleared.buildings[id].operating_fraction
	check(absf(solar_after - solar_normal) < 1e-9 and cleared.buildings[farm].power_requested_kw > 0.0, "solar output and farm load recover after the storm")
	check(not cleared.buildings[disabled_by_player].enabled, "a module the player disabled stays disabled")
	check(not send(sim, "set_storm_response", {"response": "save_power"}).success, "no response outside a storm")
	var count: int = view.count
	for i in 3000: sim.step(1.0)
	check(sim.get_storm_state().status == "cooldown" and sim.get_storm_state().count == count, "no new storm during the cooldown")
	print("DUST_STORM_RESULT checks=%d failures=%d" % [checks, failures.size()])
	if failures.is_empty(): print("DUST_STORM_PASS checks=", checks)
	quit(0 if failures.is_empty() else 1)
