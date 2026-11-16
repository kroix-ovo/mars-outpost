extends SceneTree
## Package 2: mission clock, scheduler, fast-forward and exact stable-interval replay.
## Success marker: CAMPAIGN_TIME_PASS. `-- --quick` skips the full-day oracle only.
const Harness = preload("res://tests/campaign/time_harness.gd")
const Campaign = preload("res://scripts/campaign/campaign_schema.gd")
const Calendar = preload("res://scripts/campaign/campaign_calendar.gd")
const Scheduler = preload("res://scripts/campaign/campaign_scheduler.gd")
const Hook = preload("res://scripts/campaign/campaign_time_hook.gd")
const Bridge = preload("res://scripts/world/sim_bridge.gd")
const DAY := 86400
const SUSTAINABLE := "time_sustainable_6crew"
var checks := 0
var failures: Array[String] = []

class RefusingHook extends Hook:
	func id() -> String: return "test_unmodeled"

class LeakHook extends Hook:
	## A registered system with a real per-tick ledger effect and a certified stable flow.
	func id() -> String: return "test_leak"
	func integration() -> String: return "aggregate"
	func detailed_interval(_candidate: RefCounted, ledger: RefCounted) -> Dictionary:
		return ledger.apply_system({"effect_id": "tick:%d:leak:test" % ledger.tick, "kind": "external_sink", "owner_id": "test_leak",
			"scope": "tick", "debits": {"base/oxygen_kg": 0.0001}, "credits": {"sink/environment/oxygen_kg": 0.0001}})
	func aggregate_interval(_context: Dictionary) -> Dictionary: return {"ok": true, "reason": ""}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("CAMPAIGN_TIME_FAIL ", label)

func cmd(id: String, type: String, payload: Dictionary) -> Dictionary:
	return Harness.command(id, type, payload)

func resolve(sim: RefCounted, id: String, type: String, payload: Dictionary) -> Dictionary:
	var accepted: Dictionary = sim.submit_command(cmd(id, type, payload))
	if not accepted.accepted: return {"success": false, "code": accepted.code, "accepted": false}
	sim.process_pending_commands()
	return sim._journal[id].result

func pair(preset: String, crew: bool = false) -> Array:
	## [oracle, auto, oracle events, auto events]
	var result: Array = []
	for mode in ["detailed", "auto"]:
		result.append(Harness.new_sim(preset, crew, mode))
	for index in 2:
		var events: Array = []
		result[index].game_event.connect(func(event): events.append(event))
		result.append(events)
	return result

func same_runs(label: String, runs: Array) -> void:
	var oracle_save: Dictionary = runs[0].export_save()
	var auto_save: Dictionary = runs[1].export_save()
	var worst := Harness.max_deviation(runs[0].get_snapshot(), runs[1].get_snapshot())
	check(Campaign.canonical(oracle_save) == Campaign.canonical(auto_save), label + ": identical full checkpoint (state, journal, receipts, RNG, queue)")
	check(JSON.stringify(runs[2]) == JSON.stringify(runs[3]), label + ": identical events, IDs and order")
	check(worst.abs == 0.0 and worst.rel == 0.0, label + ": continuous quantities within declared tolerance (abs 0, rel 0)")
	check(runs[0].get_time_stats().aggregate_intervals == 0, label + ": oracle used detailed stepping only")
	var draws: Array = [[], []]
	for index in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = runs[index]._state.rng.seed
		rng.state = runs[index]._state.rng.state
		for i in 3: draws[index].append(rng.randi())
	check(draws[0] == draws[1], label + ": identical RNG continuation")
	var stats: Dictionary = runs[1].get_time_stats()
	print("TIME_EQUIV %s tick=%d events=%d max_abs=%s max_rel=%s auto_detailed_ticks=%d auto_intervals=%d auto_replayed_ticks=%d rejections=%d" % [
		label, int(runs[1].get_snapshot().clock.tick_index), runs[3].size(), str(worst.abs), str(worst.rel),
		stats.detailed_ticks, stats.aggregate_intervals, stats.aggregate_ticks, stats.aggregate_rejections])

func both_through(runs: Array, prefix: String, target: int) -> Array:
	var stops: Array = []
	for index in 2: stops.append(Harness.fast_forward_through(runs[index], prefix, target))
	check(JSON.stringify(stops[0]) == JSON.stringify(stops[1]), prefix + ": identical stop reasons and ticks")
	return stops[1]

func run() -> void:
	var started := Time.get_ticks_msec()
	calendar_and_profile()
	pacing_and_bridge()
	command_validation()
	paused_and_cancel()
	equivalence_scenarios()
	scheduler_rng_order()
	hooks()
	ordinary_advance()
	save_mid_fast_forward()
	schema_and_migration()
	bounded_frame_work()
	long_horizons()
	if "--quick" in OS.get_cmdline_user_args(): print("TIME_NOTE full-day oracle skipped by --quick")
	else: stable_day_oracle()
	print("CAMPAIGN_TIME_RESULT checks=%d failures=%d wall_s=%.1f" % [checks, failures.size(), float(Time.get_ticks_msec() - started) / 1000.0])
	# The marker is absent unless the full suite, including the day oracle, ran clean.
	if failures.is_empty() and "--quick" not in OS.get_cmdline_user_args(): print("CAMPAIGN_TIME_PASS checks=", checks)
	elif failures.is_empty(): print("CAMPAIGN_TIME_QUICK_OK checks=", checks)
	quit(0 if failures.is_empty() else 1)

# ---------------------------------------------------------------- calendar, profile, pacing

func calendar_and_profile() -> void:
	var calendar := {"day_seconds": 86400, "month_days": 30, "shipment_days": 180, "campaign_days": 720}
	var first := Calendar.describe(calendar, 0)
	check(first.mission_day == 1 and first.month == 1 and first.day_of_month == 1 and first.hour == 0, "calendar starts on day 1 month 1")
	check(first.next_shipment_s == 180 * DAY and first.next_order_deadline_s == 150 * DAY and first.shipments_arrived == 0, "first shipment day 180, order deadline day 150")
	var late := Calendar.describe(calendar, DAY - 1)
	check(late.mission_day == 1 and late.hour == 23 and late.minute == 59, "last second of day 1")
	check(Calendar.describe(calendar, DAY).mission_day == 2, "day rolls at 86,400 seconds")
	var month := Calendar.describe(calendar, 30 * DAY)
	check(month.month == 2 and month.day_of_month == 1, "month is 30 mission days")
	var past_deadline := Calendar.describe(calendar, 150 * DAY)
	check(past_deadline.next_order_deadline_cycle == 2 and past_deadline.next_order_deadline_s == 330 * DAY and past_deadline.next_shipment_cycle == 1, "deadline passes before its shipment")
	var arrived := Calendar.describe(calendar, 180 * DAY)
	check(arrived.shipments_arrived == 1 and arrived.next_shipment_s == 360 * DAY and arrived.mission_day == 181, "second cycle after first arrival")
	check(Calendar.describe(calendar, 720 * DAY).campaign_complete and not Calendar.describe(calendar, 720 * DAY - 1).campaign_complete, "campaign length is 720 days")
	var sim = Harness.new_sim(SUSTAINABLE)
	var live: Dictionary = sim.get_calendar()
	check(live.ok and live.paused and live.rate_sim_s_per_real_s == 0 and live.normal_rate_sim_s_per_real_s == 120 and live.player_multipliers == [1, 5, 20], "campaign starts paused at 120x normal pace")
	var time: Dictionary = sim.get_snapshot().campaign.time
	check(time.profile_id == "campaign_default" and time.queue.size() == 3 and not time.fast_forward.active, "initial time partition")
	check(time.queue[0].kind == "day_start" and time.queue[0].due_tick == DAY and time.queue[1].kind == "shipment_order_deadline" and time.queue[1].due_tick == 150 * DAY and time.queue[2].kind == "shipment_arrival" and time.queue[2].due_tick == 180 * DAY, "calendar boundaries queued in order")
	check(sim.get_snapshot().campaign.schema_version == 2 and sim.get_snapshot().campaign.cargo.next_arrival_s == 180 * DAY, "partition schema 2; cargo partition untouched")
	var caps: Dictionary = sim.get_capabilities()
	check(caps.fast_forward and caps.owns_time_pacing and not caps.campaign_gameplay and not caps.agriculture, "capabilities: fast-forward real, gameplay still false")
	check(caps.time_integration.power == "aggregate" and caps.time_integration.life_support == "aggregate" and caps.time_integration.crew_demand == "aggregate" and caps.time_integration.crew_activity == "detailed_fallback", "capabilities distinguish aggregate from fallback stepping")
	var legacy = Harness.new_sim("habitat_6crew")
	check(legacy.get_snapshot().clock.time_scale == 1 and not legacy.get_capabilities().owns_time_pacing and legacy.get_calendar().normal_rate_sim_s_per_real_s == 1, "fixture profile keeps its clock semantics")
	var bad := Harness.config(SUSTAINABLE)
	bad.definition_manifest["res://data/campaign/time_profile.json"] = "0".repeat(64)
	check(not Harness.Simulation.new().initialize(bad, null, null).ok, "changed time profile hash rejected")
	bad = Harness.config(SUSTAINABLE)
	bad.campaign_profile_path = "res://data/campaign/content.json"
	check(not Harness.Simulation.new().initialize(bad, null, null).ok, "profile outside manifest rejected")

func drain(sim: RefCounted) -> int:
	var calls := 0
	while sim._state.accumulator_s >= 1.0 and sim._state.records.clock.time_scale > 0 and calls < 100000:
		sim.advance(0.0)
		calls += 1
	return calls

func pacing_and_bridge() -> void:
	var sim = Harness.new_sim(SUSTAINABLE)
	check(sim.advance(10.0).ok and sim.get_snapshot().clock.tick_index == 0 and sim._state.accumulator_s == 0.0, "paused: real time adds no survival time")
	var expected := 0
	for scale in [1, 5, 20]:
		check(resolve(sim, "scale_%d" % scale, "set_time_scale", {"time_scale": scale}).success, "set multiplier %d" % scale)
		check(sim.advance(1.0).ok, "advance one real second at %dx" % scale)
		drain(sim)
		expected += 120 * scale
		check(sim.get_snapshot().clock.tick_index == expected, "one real second at %dx is %d simulated seconds" % [scale, 120 * scale])
		check(sim.get_calendar().rate_sim_s_per_real_s == 120 * scale, "calendar reports the effective rate")
	check(not resolve(sim, "scale_bad", "set_time_scale", {"time_scale": 2}).get("accepted", true), "only 0/1/5/20 multipliers exist")
	resolve(sim, "scale_one", "set_time_scale", {"time_scale": 1})
	sim.advance(0.0125)
	check(sim.get_snapshot().clock.tick_index == expected + 1 and absf(sim._state.accumulator_s - 0.5) < 1e-9, "fractional second stays in the accumulator")
	check(not sim.advance(-1.0).ok and not sim.advance(NAN).ok and not sim.advance(1.0e300).ok and not sim.advance_budgeted(1.0, 0).ok, "invalid deltas and budgets rejected")
	# The wrapper must not multiply time a second time for a facade that owns pacing.
	check(Bridge.paced_delta(0.5, 5, true) == 0.5 and Bridge.paced_delta(0.5, 0, true) == 0.5, "bridge passes real seconds to a pacing-owning backend")
	check(Bridge.paced_delta(1.0, 1, false) == 60.0 and Bridge.paced_delta(1.0, 5, false) == 24.0 and Bridge.paced_delta(1.0, 20, false) == 12.0, "legacy 60/120/240 pacing unchanged")

# ---------------------------------------------------------------- commands

func command_validation() -> void:
	var sim = Harness.new_sim(SUSTAINABLE)
	var before := Harness.canonical(sim)
	for payload in [{}, {"target_elapsed_s": 100, "extra": 1}, {"target_elapsed_s": 1.5}, {"target_elapsed_s": 0}, {"target_elapsed_s": -5}, {"target_elapsed_s": "100"}, {"target_elapsed_s": 1.0e300}, {"target": 100}]:
		check(not sim.submit_command(cmd("bad", "request_fast_forward", payload)).accepted, "strict request payload rejected: " + str(payload))
	check(not sim.submit_command(cmd("bad", "cancel_fast_forward", {"x": 1})).accepted, "strict cancel payload rejected")
	var v2 := cmd("bad", "request_fast_forward", {"target_elapsed_s": 100})
	v2.contract_version = "2.0.0"
	check(not sim.submit_command(v2).accepted, "v2 envelope rejected")
	check(not sim.submit_command(cmd("bad", "jump_time", {})).accepted, "unknown command rejected")
	check(Harness.canonical(sim) == before, "rejected submissions change nothing")
	# Earlier/equal targets are valid envelopes that fail on resolution, leaving state unchanged.
	var first := Harness.fast_forward(sim, "ff_a", 240)
	check(first.ok and first.stop_reason == "target_reached" and first.tick == 240, "fast-forward reaches its target while paused")
	var revision: int = sim.get_snapshot().revision
	var earlier := resolve(sim, "ff_early", "request_fast_forward", {"target_elapsed_s": 100})
	check(not earlier.success and earlier.code == "invalid_value", "earlier target fails on resolution")
	check(not resolve(sim, "ff_equal", "request_fast_forward", {"target_elapsed_s": 240}).success, "equal target fails")
	check(sim.get_snapshot().revision == revision and sim.get_snapshot().campaign.time.fast_forward.command_id == "ff_a", "failed requests leave the committed record")
	check(resolve(sim, "ff_b", "request_fast_forward", {"target_elapsed_s": 100000}).success, "second request accepted")
	var again := resolve(sim, "ff_c", "request_fast_forward", {"target_elapsed_s": 200000})
	check(not again.success and again.code == "invalid_state" and sim.get_snapshot().campaign.time.fast_forward.target_tick == 100000, "request during an active fast-forward fails and keeps the committed target")
	var duplicate: Dictionary = sim.submit_command(cmd("ff_b", "request_fast_forward", {"target_elapsed_s": 100000}))
	check(duplicate.accepted and duplicate.duplicate and duplicate.result.success, "retry deduplicates")
	check(not sim.submit_command(cmd("ff_b", "request_fast_forward", {"target_elapsed_s": 100001})).accepted, "conflicting retry rejected")
	check(sim.submit_command(cmd("ff_b", "request_fast_forward", {"target_elapsed_s": 100000.0})).duplicate, "5 and 5.0 normalize identically")

func paused_and_cancel() -> void:
	var sim = Harness.new_sim(SUSTAINABLE)
	var events: Array = []
	sim.game_event.connect(func(event): events.append(event))
	check(sim.get_snapshot().clock.time_scale == 0, "starts paused")
	var building: String = sim.get_snapshot().buildings.keys()[0]
	sim.submit_command(cmd("off", "set_building_enabled", {"building_id": building, "enabled": false}))
	sim.submit_command(cmd("ff", "request_fast_forward", {"target_elapsed_s": 500000}))
	sim.process_pending_commands()
	var snapshot: Dictionary = sim.get_snapshot()
	check(not snapshot.buildings[building].enabled and snapshot.campaign.time.fast_forward.active and snapshot.clock.tick_index == 0, "paused queue resolves commands without advancing time")
	check(events.size() == 3 and events[0].type == "command_result" and events[1].type == "command_result" and events[2].type == "fast_forward_started", "command results in receive order")
	sim.advance(0.0)
	var mid: int = sim.get_snapshot().clock.tick_index
	check(mid > 0 and mid < 500000 and sim.get_snapshot().campaign.time.fast_forward.active, "requested fast-forward runs in bounded steps")
	var cancelled := resolve(sim, "stop", "cancel_fast_forward", {})
	var ff: Dictionary = sim.get_snapshot().campaign.time.fast_forward
	check(cancelled.success and cancelled.data.cancelled and not ff.active and ff.stop_reason == "cancelled" and ff.stopped_tick == mid and ff.target_tick == 500000, "cancel records reason, tick and committed target")
	sim.advance(5.0)
	check(sim.get_snapshot().clock.tick_index == mid, "cancelled and paused: time stays put")
	var noop := resolve(sim, "stop_again", "cancel_fast_forward", {})
	check(noop.success and not noop.data.cancelled, "cancel with nothing active is a successful no-op")
	check(events[-2].type == "fast_forward_stopped" and events[-2].data.reason == "cancelled", "stop event emitted once")
	# Pausing stops a running fast-forward: pause never advances survival time.
	resolve(sim, "run", "set_time_scale", {"time_scale": 1})
	resolve(sim, "ff2", "request_fast_forward", {"target_elapsed_s": 900000})
	sim.advance(0.0)
	resolve(sim, "pause", "set_time_scale", {"time_scale": 0})
	ff = sim.get_snapshot().campaign.time.fast_forward
	var paused_at: int = sim.get_snapshot().clock.tick_index
	check(not ff.active and ff.stop_reason == "paused" and ff.stopped_tick == paused_at, "pause stops fast-forward with its reason")
	sim.advance(1.0)
	check(sim.get_snapshot().clock.tick_index == paused_at, "nothing advances after the pause")

# ---------------------------------------------------------------- oracle equivalence

func equivalence_scenarios() -> void:
	var runs := pair("time_battery_near_full_6crew")
	both_through(runs, "battery", 3000)
	check(runs[1].get_snapshot().power.battery_stored_kwh == 40.0, "battery saturated at capacity")
	check(runs[1].get_time_stats().aggregate_intervals >= 2, "replay used before and after battery saturation")
	same_runs("battery_saturation", runs)

	runs = pair("time_food_exhaustion_6crew")
	var stops := both_through(runs, "food", 2500)
	check(stops.size() >= 2 and stops[0][0] == "danger" and stops[0][1].begins_with("unmet_need:") and stops[0][2] == 501, "fast-forward stops on the tick food runs out")
	check(stops[-1][0] == "target_reached" and stops[-1][2] == 2500, "continues to the target when asked again")
	var shortage := 0
	for event in runs[3]:
		if event.type == "resource_shortage": shortage += 1
	check(shortage == 6 and runs[1].get_snapshot().resources.food_kcal.amount == 0.0, "reserve exhaustion: six shortage events, empty reserve")
	same_runs("reserve_exhaustion", runs)

	runs = pair("power_shortage_6crew")
	stops = both_through(runs, "power", 3000)
	var danger := 0
	for stop in stops:
		if stop[0] == "danger": danger += 1
	check(danger >= 1, "production shortage raises danger stops")
	same_runs("production_shortage_power", runs)

	runs = pair("habitat_5crew")
	both_through(runs, "inputs", 2000)
	same_runs("production_shortage_inputs", runs)

	runs = pair("storage_limits_6crew")
	# As in the legacy storage script: with the recycler off, wastewater storage fills.
	for index in 2: check(resolve(runs[index], "recycler_off", "set_building_enabled", {"building_id": "building_000004", "enabled": false}).success, "recycler disabled")
	stops = both_through(runs, "storage", 2000)
	var codes := {}
	for alert in runs[1].get_snapshot().alerts: codes[alert.code] = true
	check(codes.has("storage_full") and runs[1]._state.crew_demand.wastewater_overflow_kg > 0.0, "storage overflow reached and recorded")
	same_runs("storage_overflow", runs)

	# Travel and labor stay on detailed stepping, then replay resumes after completion.
	runs = pair("salvage_6crew", true)
	for index in 2:
		var placed := resolve(runs[index], "build", "place_building", {"definition_id": "fixture_generator", "cell": [10, 10], "rotation_quarters": 0})
		check(placed.success, "construction placed")
		check(resolve(runs[index], "assign", "assign_task", {"task_id": placed.data.task_id, "crew_ids": ["crew_000001"], "priority": 50}).success, "crew assigned")
	both_through(runs, "crew", 600)
	var commissioned := false
	for event in runs[3]:
		if event.type == "building_commissioned": commissioned = true
	var fallback: Dictionary = runs[1].get_time_stats().fallback_reasons
	check(commissioned and (fallback.has("crew_activity:travelling") or fallback.has("crew_activity:working")), "travel/work completion handled by detailed fallback, and reported")
	check(runs[1].get_time_stats().aggregate_intervals >= 1, "replay resumes once the crew is idle")
	same_runs("crew_travel_and_labor", runs)

	runs = pair("salvage_6crew", true)
	for index in 2:
		check(resolve(runs[index], "launch", "start_eva", {"site_id": "site_cargo_a", "crew_ids": ["crew_000001", "crew_000002"], "work_duration_s": 2.0, "oxygen_kg_per_crew": 0.12, "battery_kwh_per_crew": 0.006}).success, "expedition launched")
	both_through(runs, "eva", 400)
	check(runs[1].get_snapshot().expeditions.values()[0].status == "completed", "expedition completed during fast-forward")
	same_runs("expedition", runs)

func scheduler_rng_order() -> void:
	var runs := pair(SUSTAINABLE)
	var handler := func(state: RefCounted, entry: Dictionary) -> Dictionary:
		# Random outcomes are drawn at the scheduled boundary, never per rendered frame.
		var roll: int = state.rng.randi()
		Scheduler.schedule(state.records.campaign.time, int(entry.due_tick) + 7000, "test_random", {"count": int(entry.payload.count) + 1})
		return {"ok": true, "events": [{"type": "test_roll", "entity_ids": [], "data": {"roll": str(roll), "count": entry.payload.count}}],
			"stop": {"reason": "scheduled", "detail": "test"} if int(entry.payload.count) == 2 else null}
	var validator := func(payload: Dictionary) -> bool: return payload.size() == 1 and payload.get("count") is int
	for index in 2:
		check(runs[index].register_boundary_handler("test_random", handler, validator).ok, "boundary kind registered")
		check(not runs[index].register_boundary_handler("day_start", handler).ok and not runs[index].register_boundary_handler("test_random", handler).ok, "built-in and duplicate kinds refused")
		check(not runs[index].schedule_boundary(0, "test_random", {"count": 0}).ok and not runs[index].schedule_boundary(1000, "unknown", {}).ok and not runs[index].schedule_boundary(1000, "test_random", {"bad": 1}).ok, "invalid scheduling refused")
		check(runs[index].schedule_boundary(1000, "test_random", {"count": 0}).ok, "boundary scheduled")
		# Scheduled later but with a lower phase: it must fire first on the shared tick.
		check(runs[index].schedule_boundary(8000, "test_random", {"count": 100}, 5).ok, "same-tick boundary scheduled")
	var stops := both_through(runs, "rng", 16000)
	check(stops[0][0] == "scheduled" and stops[0][2] == 15000 and stops[-1] == ["target_reached", "", 16000], "a registered boundary can stop fast-forward")
	var order: Array = []
	for event in runs[3]:
		if event.type == "test_roll": order.append([event.tick_index, event.data.count])
	check(order == [[1000, 0], [8000, 100], [8000, 1], [15000, 101], [15000, 2]], "boundaries fire in (due tick, phase, sequence) order: " + str(order))
	var rolls := order.size()
	check(rolls == 5 and runs[1]._state.rng.state != RandomNumberGenerator.new().state, "scheduled draws happened")
	same_runs("scheduled_rng_boundaries", runs)
	var saved: Dictionary = runs[1].export_save()
	check(not Harness.new_sim(SUSTAINABLE).import_save(saved).ok, "checkpoint with an unregistered boundary kind is rejected")
	var restored = Harness.new_sim(SUSTAINABLE)
	restored.register_boundary_handler("test_random", handler, validator)
	check(restored.import_save(JSON.parse_string(JSON.stringify(saved, "", true, true))).ok and Harness.canonical(restored) == Campaign.canonical(saved), "pending transitions and their order survive a disk roundtrip")

func hooks() -> void:
	var runs := pair(SUSTAINABLE)
	for index in 2: check(runs[index].register_time_hook(RefusingHook.new()).ok, "hook registered")
	check(not runs[1].register_time_hook(RefusingHook.new()).ok, "duplicate hook refused")
	both_through(runs, "refuse", 3000)
	var stats: Dictionary = runs[1].get_time_stats()
	check(stats.aggregate_intervals == 0 and stats.detailed_ticks == 3000 and stats.fallback_reasons.has("test_unmodeled:no_aggregate_model"), "a system without an aggregate model forces detailed stepping and says why")
	check(runs[1].get_capabilities().time_integration.test_unmodeled == "detailed_fallback", "fallback is visible in capabilities")
	same_runs("unmodeled_hook_fallback", runs)

	runs = pair(SUSTAINABLE)
	for index in 2: runs[index].register_time_hook(LeakHook.new())
	both_through(runs, "leak", 5000)
	var plain = Harness.new_sim(SUSTAINABLE)
	Harness.fast_forward_through(plain, "leak", 5000)
	check(runs[1].get_snapshot().resources.oxygen_kg.amount < plain.get_snapshot().resources.oxygen_kg.amount, "registered system's detailed interval has a real ledger effect")
	check(runs[1].get_time_stats().aggregate_intervals >= 1, "certified registered flow is replayed")
	same_runs("registered_hook_flow", runs)

func ordinary_advance() -> void:
	# Ordinary play (no fast-forward) at 20x, with exactly representable frame deltas.
	var runs := pair(SUSTAINABLE)
	for index in 2:
		resolve(runs[index], "fast", "set_time_scale", {"time_scale": 20})
		for frame in 10: check(runs[index].advance(0.25).ok, "ordinary frame")
		drain(runs[index])
	check(runs[1].get_snapshot().clock.tick_index == 6000 and runs[1].get_time_stats().aggregate_intervals > 0, "ordinary 20x play uses replay too")
	same_runs("ordinary_advance_20x", runs)
	# Frame splitting must not change results: one unit per call against the default budget.
	var chunked = Harness.new_sim(SUSTAINABLE)
	var chunk_events: Array = []
	chunked.game_event.connect(func(event): chunk_events.append(event))
	resolve(chunked, "fast", "set_time_scale", {"time_scale": 20})
	for frame in 10: chunked.advance_budgeted(0.25, 1)
	var calls := 0
	while chunked._state.accumulator_s >= 1.0 and calls < 100000:
		chunked.advance_budgeted(0.0, 1)
		calls += 1
	check(Harness.canonical(chunked) == Harness.canonical(runs[1]) and JSON.stringify(chunk_events) == JSON.stringify(runs[3]), "results independent of wrapper frame splitting")

# ---------------------------------------------------------------- persistence

func save_mid_fast_forward() -> void:
	var sim = Harness.new_sim(SUSTAINABLE)
	sim._state.accumulator_s = 0.375
	sim.submit_command(cmd("ff", "request_fast_forward", {"target_elapsed_s": 9000}))
	sim.advance(0.0)
	var mid: int = sim.get_snapshot().clock.tick_index
	check(mid > 0 and mid < 9000 and sim.get_snapshot().campaign.time.fast_forward.active, "checkpoint taken mid fast-forward")
	sim.submit_command(cmd("queued", "set_time_scale", {"time_scale": 5}))
	var text := JSON.stringify(sim.export_save(), "", true, true)
	var copies: Array = [sim]
	for mode in ["auto", "detailed"]:
		var restored = Harness.new_sim(SUSTAINABLE, false, mode)
		var loaded: Dictionary = restored.import_save(JSON.parse_string(text))
		check(loaded.ok and loaded.migrated_from == null, "mid fast-forward checkpoint loads: " + loaded.get("reason", ""))
		check(JSON.stringify(restored.export_save(), "", true, true) == text, "accumulator, target, queue and pending command preserved")
		check(restored.submit_command(cmd("ff", "request_fast_forward", {"target_elapsed_s": 9000})).duplicate, "fast-forward command deduplicates across reload")
		copies.append(restored)
	for copy in copies:
		var calls := 0
		while copy._state.records.campaign.time.fast_forward.active and calls < 100000:
			copy.advance(0.0)
			calls += 1
	var ff: Dictionary = sim.get_snapshot().campaign.time.fast_forward
	check(ff.stop_reason == "target_reached" and ff.stopped_tick == 9000 and sim.get_snapshot().clock.time_scale == 5 and sim._state.accumulator_s == 0.375, "continued to the committed target with the accumulator intact")
	check(Harness.canonical(copies[1]) == Harness.canonical(sim), "restored replay continuation identical")
	check(Harness.canonical(copies[2]) == Harness.canonical(sim), "restored detailed continuation identical")

func reject_unchanged(sim: RefCounted, record: Dictionary, label: String) -> void:
	var before := Harness.canonical(sim)
	check(not sim.import_save(record).ok, label + " rejected")
	check(Harness.canonical(sim) == before, label + " leaves the runtime unchanged")

func schema_and_migration() -> void:
	var sim = Harness.new_sim(SUSTAINABLE)
	Harness.fast_forward(sim, "ff", 100000)
	sim.submit_command(cmd("ff2", "request_fast_forward", {"target_elapsed_s": 300000}))
	sim.advance(0.0)
	var saved: Dictionary = sim.export_save()
	var time_path := func(record: Dictionary) -> Dictionary: return record.state.records.campaign.time
	var bad := saved.duplicate(true)
	time_path.call(bad).queue[0].due_tick = 5
	reject_unchanged(sim, bad, "boundary due in the past")
	bad = saved.duplicate(true)
	time_path.call(bad).queue[0].kind = "invented"
	reject_unchanged(sim, bad, "unknown boundary kind")
	bad = saved.duplicate(true)
	time_path.call(bad).queue.remove_at(2)
	reject_unchanged(sim, bad, "missing shipment boundary")
	bad = saved.duplicate(true)
	time_path.call(bad).queue.reverse()
	reject_unchanged(sim, bad, "reordered boundaries")
	bad = saved.duplicate(true)
	time_path.call(bad).queue[1].sequence = time_path.call(bad).next_sequence
	reject_unchanged(sim, bad, "boundary identity beyond the counter")
	bad = saved.duplicate(true)
	time_path.call(bad).queue[2].payload = {"cycle": 2}
	reject_unchanged(sim, bad, "shipment cycle disagrees with the clock")
	bad = saved.duplicate(true)
	time_path.call(bad).fast_forward.stop_reason = "target_reached"
	reject_unchanged(sim, bad, "active fast-forward with a stop reason")
	bad = saved.duplicate(true)
	time_path.call(bad).fast_forward.target_tick = 10
	reject_unchanged(sim, bad, "fast-forward target behind the clock")
	bad = saved.duplicate(true)
	time_path.call(bad).fast_forward.erase("stop_detail")
	reject_unchanged(sim, bad, "incomplete fast-forward record")
	bad = saved.duplicate(true)
	time_path.call(bad).base_rate = 60
	reject_unchanged(sim, bad, "pace differs from the hashed profile")
	bad = saved.duplicate(true)
	time_path.call(bad).extra = true
	reject_unchanged(sim, bad, "unknown time field")
	bad = saved.duplicate(true)
	bad.journal.ff2.normalized.payload.target_elapsed_s = 1.5
	reject_unchanged(sim, bad, "invalid journaled v3 command")
	bad = saved.duplicate(true)
	bad.state.records.campaign.schema_version = 3
	reject_unchanged(sim, bad, "newer partition schema")
	var legacy = Harness.new_sim("habitat_6crew")
	check(legacy.import_save(saved).ok and legacy.get_capabilities().owns_time_pacing and Harness.canonical(legacy) == Campaign.canonical(saved), "a checkpoint carries its own time profile")
	# Development-save policy: foundation (schema 1) partitions gain the default time record.
	var fresh = Harness.new_sim(SUSTAINABLE)
	var v1: Dictionary = fresh.export_save()
	v1.state.records.campaign.erase("time")
	v1.state.records.campaign.schema_version = 1
	var target = Harness.new_sim(SUSTAINABLE)
	Harness.fast_forward(target, "moved", 500)
	var migrated: Dictionary = target.import_save(JSON.parse_string(JSON.stringify(v1, "", true, true)))
	check(migrated.ok and migrated.migrated_from == 1 and Harness.canonical(target) == Harness.canonical(fresh), "schema 1 checkpoint at tick 0 migrates to the initial time partition")
	var later: Dictionary = sim.export_save()
	later.state.records.campaign.erase("time")
	later.state.records.campaign.schema_version = 1
	check(target.import_save(later).ok, "schema 1 checkpoint at a later tick migrates")
	var queue: Array = target.get_snapshot().campaign.time.queue
	var now: int = target.get_snapshot().clock.tick_index
	check(queue[0].due_tick == Calendar.next_day_start(target.get_snapshot().campaign.calendar, now) and queue[1].due_tick == 150 * DAY and queue[2].due_tick == 180 * DAY and not target.get_snapshot().campaign.time.fast_forward.active, "migration derives pending boundaries from the checkpoint's own tick")
	var half: Dictionary = fresh.export_save()
	half.state.records.campaign.schema_version = 1
	reject_unchanged(target, half, "schema 1 partition that already has a time record")

# ---------------------------------------------------------------- frame bounds and long horizons

func bounded_frame_work() -> void:
	var sim = Harness.new_sim(SUSTAINABLE)
	var profile: Dictionary = sim._profile
	sim.submit_command(cmd("ff", "request_fast_forward", {"target_elapsed_s": 2 * DAY}))
	var calls := 0
	var worst_ticks := 0
	var started := Time.get_ticks_usec()
	while calls < 100000:
		var before: int = sim._state.records.clock.tick_index
		check(sim.advance_budgeted(0.0, 8000).ok, "budgeted fast-forward call")
		worst_ticks = maxi(worst_ticks, int(sim._state.records.clock.tick_index) - before)
		calls += 1
		if not sim._state.records.campaign.time.fast_forward.active: break
	var wall_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var stats: Dictionary = sim.get_time_stats()
	check(calls > 4 and sim.get_snapshot().clock.tick_index == 2 * DAY, "two days need several bounded calls")
	check(stats.max_call_detailed_ticks <= int(profile.max_detailed_ticks_per_advance) and stats.max_call_account_ticks <= int(profile.max_aggregate_account_ticks_per_advance), "per-call work stays within the profile budgets")
	check(stats.detailed_ticks + stats.aggregate_ticks == 2 * DAY, "every simulated second is either a real tick or a verified replayed tick")
	print("TIME_FRAME simulated_s=%d wall_ms=%.1f calls=%d detailed_ticks=%d aggregate_intervals=%d max_call_detailed_ticks=%d max_call_account_ticks=%d max_call_ticks=%d max_call_usec=%d" % [
		2 * DAY, wall_ms, calls, stats.detailed_ticks, stats.aggregate_intervals, stats.max_call_detailed_ticks, stats.max_call_account_ticks, worst_ticks, stats.max_call_usec])
	var legacy = Harness.new_sim("habitat_6crew")
	legacy.advance(100000.0)
	check(legacy.get_snapshot().clock.tick_index == 120 and legacy._state.accumulator_s == 100000.0 - 120.0, "fixture profile keeps the 120-tick cap and its backlog")

func window(checkpoint: Dictionary, ticks: int, label: String) -> void:
	## Oracle window: both modes continue from one aggregate checkpoint and must agree.
	var runs: Array = []
	for mode in ["detailed", "auto"]:
		var sim = Harness.new_sim(SUSTAINABLE, false, mode)
		check(sim.import_save(checkpoint).ok, label + ": window checkpoint loads")
		runs.append(sim)
	for index in 2:
		var events: Array = []
		runs[index].game_event.connect(func(event): events.append(event))
		runs.append(events)
	var target: int = int(runs[0].get_snapshot().clock.tick_index) + ticks
	both_through(runs, "window", target)
	check(Harness.canonical(runs[0]) == Harness.canonical(runs[1]) and JSON.stringify(runs[2]) == JSON.stringify(runs[3]), label + ": oracle window identical")

func long_horizons() -> void:
	# Week: daily targets, with an oracle window after every stop and one across battery saturation.
	var sim = Harness.new_sim(SUSTAINABLE)
	var events: Array = []
	sim.game_event.connect(func(event): events.append(event))
	var started := Time.get_ticks_usec()
	Harness.fast_forward(sim, "pre_saturation", 87800)
	window(sim.export_save(), 600, "battery saturation on day 2")
	for day in range(1, 8):
		if day * DAY > int(sim.get_snapshot().clock.tick_index):
			var run := Harness.fast_forward(sim, "week_%d" % day, day * DAY)
			check(run.stop_reason == "target_reached" and run.tick == day * DAY, "week day %d reached" % day)
		window(sim.export_save(), 150, "week day %d" % day)
	var stats: Dictionary = sim.get_time_stats()
	print("TIME_HORIZON week simulated_s=%d wall_ms=%.1f detailed_ticks=%d aggregate_intervals=%d rejections=%d advance_calls=%d max_call_detailed_ticks=%d max_call_account_ticks=%d max_call_usec=%d" % [
		7 * DAY, float(Time.get_ticks_usec() - started) / 1000.0, stats.detailed_ticks, stats.aggregate_intervals, stats.aggregate_rejections, stats.advance_calls, stats.max_call_detailed_ticks, stats.max_call_account_ticks, stats.max_call_usec])
	check(sim.get_snapshot().power.battery_stored_kwh == 40.0 and sim.get_calendar().mission_day == 8, "week ends on day 8 with a full battery")
	# First 180-day boundary. Declared sustainable stocks: no food is produced.
	started = Time.get_ticks_usec()
	var stops: Array = Harness.fast_forward_through(sim, "cycle", 200 * DAY)
	check(stops.size() == 3 and stops[0] == ["deadline", "shipment_order:1", 150 * DAY] and stops[1] == ["shipment", "cycle:1", 180 * DAY] and stops[2] == ["target_reached", "", 200 * DAY],
		"fast-forward stops at the day-150 order deadline, the day-180 shipment, then the target: " + JSON.stringify(stops))
	stats = sim.get_time_stats()
	print("TIME_HORIZON shipment simulated_s=%d wall_ms=%.1f detailed_ticks=%d aggregate_intervals=%d rejections=%d advance_calls=%d max_call_detailed_ticks=%d max_call_account_ticks=%d max_call_usec=%d" % [
		200 * DAY, float(Time.get_ticks_usec() - started) / 1000.0, stats.detailed_ticks, stats.aggregate_intervals, stats.aggregate_rejections, stats.advance_calls, stats.max_call_detailed_ticks, stats.max_call_account_ticks, stats.max_call_usec])
	print("TIME_FALLBACKS ", JSON.stringify(stats.fallback_reasons))
	var days := 0
	var months := 0
	var due := 0
	for event in events:
		if event.type == "calendar_day": days += 1
		elif event.type == "calendar_month": months += 1
		elif event.type == "shipment_due": due += 1
	var calendar: Dictionary = sim.get_calendar()
	check(days == 200 and months == 6 and due == 1 and calendar.mission_day == 201 and calendar.shipments_arrived == 1 and calendar.next_shipment_s == 360 * DAY, "200 day boundaries, 6 month boundaries, one shipment boundary")
	var snapshot: Dictionary = sim.get_snapshot()
	check(snapshot.alerts.is_empty() and sim._state.crew_demand.unmet_needs.is_empty() and snapshot.resources.food_kcal.amount > 0.0, "declared sustainable conditions hold for 200 days")
	check(snapshot.campaign.cargo.next_arrival_s == 180 * DAY and snapshot.campaign.cargo.delivered_cycles.is_empty(), "cargo delivery itself remains package 9")
	check(stats.aggregate_rejections == 0, "no replayed interval failed verification")
	window(sim.export_save(), 300, "after the 180-day boundary")
	check(sim.import_save(JSON.parse_string(JSON.stringify(sim.export_save(), "", true, true))).ok, "day-200 checkpoint roundtrips")

func stable_day_oracle() -> void:
	var runs := pair(SUSTAINABLE)
	var walls: Array = []
	for index in 2:
		var started := Time.get_ticks_usec()
		var run := Harness.fast_forward(runs[index], "day", DAY)
		walls.append(float(Time.get_ticks_usec() - started) / 1000.0)
		check(run.ok and run.stop_reason == "target_reached" and run.tick == DAY, "stable day reached")
	same_runs("stable_day", runs)
	var oracle: Dictionary = runs[0].get_time_stats()
	var auto: Dictionary = runs[1].get_time_stats()
	check(oracle.detailed_ticks == DAY and auto.detailed_ticks < 400 and auto.detailed_ticks + auto.aggregate_ticks == DAY, "oracle ran 86,400 real ticks; replay ran a few hundred")
	print("TIME_DAY oracle_wall_ms=%.1f oracle_detailed_ticks=%d auto_wall_ms=%.1f auto_detailed_ticks=%d auto_aggregate_intervals=%d auto_max_call_detailed_ticks=%d auto_max_call_account_ticks=%d auto_max_call_usec=%d" % [
		walls[0], oracle.detailed_ticks, walls[1], auto.detailed_ticks, auto.aggregate_intervals, auto.max_call_detailed_ticks, auto.max_call_account_ticks, auto.max_call_usec])
