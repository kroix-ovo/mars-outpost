extends RefCounted
## Shared helpers for the package 2 time suites. Drives the real v3 facade only
## through public commands and advance calls, as a wrapper would.
const Simulation = preload("res://scripts/campaign/campaign_simulation.gd")
const World = preload("res://scripts/world/world_service.gd")
const Adapter = preload("res://scripts/crew/crew_adapter.gd")
const Campaign = preload("res://scripts/campaign/campaign_schema.gd")
const CAMPAIGN_FIX := "res://tests/campaign/fixtures/init/"
const LEGACY_FIX := "res://tests/simulation/fixtures/init/"
const DAY := 86400

static func config(preset: String) -> Dictionary:
	var path := CAMPAIGN_FIX + preset + ".json"
	if not FileAccess.file_exists(path): path = LEGACY_FIX + preset + ".json"
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func new_sim(preset: String, crew: bool = false, mode: String = "auto") -> RefCounted:
	var settings := config(preset)
	var world: RefCounted = null
	var adapter: RefCounted = null
	if crew:
		var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(settings.scenario_path))
		world = World.from_files(scenario.map_path, scenario.building_definition_paths).service
		adapter = Adapter.new(world)
	var sim = Simulation.new()
	var result: Dictionary = sim.initialize(settings, world, adapter)
	if not result.ok:
		push_error("time harness initialize failed: " + str(result))
		return null
	sim.set_time_integration(mode)
	return sim

static func command(id: String, type: String, payload: Dictionary) -> Dictionary:
	return {"contract_version": "3.0.0", "command_id": id, "type": type, "payload": payload}

static func canonical(sim: RefCounted) -> String:
	return Campaign.canonical(sim.export_save())

static func fast_forward(sim: RefCounted, id: String, target: int, max_calls: int = 100000000) -> Dictionary:
	## Submit one request and call advance like a wrapper until it stops.
	var accepted: Dictionary = sim.submit_command(command(id, "request_fast_forward", {"target_elapsed_s": target}))
	if not accepted.accepted: return {"ok": false, "reason": accepted.reason, "calls": 0}
	var calls := 0
	while calls < max_calls:
		var result: Dictionary = sim.advance(0.0)
		calls += 1
		if not result.ok: return {"ok": false, "reason": result.reason, "calls": calls}
		if not sim._state.records.campaign.time.fast_forward.active: break
	var ff: Dictionary = sim.get_snapshot().campaign.time.fast_forward
	return {"ok": true, "calls": calls, "stop_reason": ff.stop_reason, "stop_detail": ff.stop_detail,
		"tick": int(sim.get_snapshot().clock.tick_index), "result": sim._journal[id].result}

static func fast_forward_through(sim: RefCounted, prefix: String, target: int) -> Array:
	## Keep requesting the same target across danger/deadline/shipment stops.
	var stops: Array = []
	while int(sim._state.records.clock.tick_index) < target and stops.size() < 64:
		var run := fast_forward(sim, "%s_%d" % [prefix, stops.size()], target)
		stops.append([run.get("stop_reason"), run.get("stop_detail"), run.get("tick")])
		if not run.ok: break
	return stops

static func max_deviation(a: Dictionary, b: Dictionary) -> Dictionary:
	## Largest absolute/relative difference over resource balances and batteries.
	var worst := {"abs": 0.0, "rel": 0.0}
	for id in a.resources:
		_deviation(worst, a.resources[id].amount, b.resources[id].amount)
	_deviation(worst, a.power.battery_stored_kwh, b.power.battery_stored_kwh)
	return worst

static func _deviation(worst: Dictionary, x: float, y: float) -> void:
	var difference := absf(x - y)
	worst.abs = maxf(worst.abs, difference)
	if maxf(absf(x), absf(y)) > 0.0: worst.rel = maxf(worst.rel, difference / maxf(absf(x), absf(y)))
