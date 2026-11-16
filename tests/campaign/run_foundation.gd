extends SceneTree
const Simulation = preload("res://scripts/campaign/campaign_simulation.gd")
const Store = preload("res://scripts/campaign/campaign_save_store.gd")
const World = preload("res://scripts/world/world_service.gd")
const Adapter = preload("res://scripts/crew/crew_adapter.gd")
const Campaign = preload("res://scripts/campaign/campaign_schema.gd")
const FIX := "res://tests/simulation/fixtures/"
var checks := 0
var failures: Array[String] = []
var notifications := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func new_sim(crew: bool = false, preset: String = "habitat_6crew") -> RefCounted:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX + "init/" + preset + ".json"))
	var world: RefCounted = null
	var adapter: RefCounted = null
	if crew:
		var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.scenario_path))
		var service := World.from_files(scenario.map_path, scenario.building_definition_paths)
		check(service.ok, "world initializes")
		world = service.service
		adapter = Adapter.new(world)
	var sim = Simulation.new()
	var result: Dictionary = sim.initialize(config, world, adapter)
	check(result.ok, "campaign initializes: " + result.get("reason", ""))
	return sim

func command(id: String, type: String, payload: Dictionary) -> Dictionary:
	return {"contract_version":"3.0.0", "command_id":id, "type":type, "payload":payload}

func same(a: Variant, b: Variant) -> bool:
	return Campaign.canonical(a) == Campaign.canonical(b)

func reject_unchanged(sim: RefCounted, record: Dictionary, label: String) -> void:
	var before: Dictionary = sim.export_save()
	var result: Dictionary = sim.import_save(record)
	check(not result.ok, label + " rejected")
	check(same(before, sim.export_save()), label + " leaves full runtime unchanged")

func run() -> void:
	for with_crew in [false, true]:
		var sim = new_sim(with_crew)
		check(sim.get_snapshot().contract_version == "3.0.0", "public v3 snapshot")
		# Package 2 implemented fast-forward; features without a production path stay false.
		check(sim.get_capabilities().persistence and sim.get_capabilities().fast_forward and not sim.get_capabilities().campaign_gameplay and not sim.get_capabilities().medical, "honest capabilities")
		var wrong := command("wrong", "set_time_scale", {"time_scale":5})
		wrong.contract_version = "2.0.0"
		check(not sim.submit_command(wrong).accepted, "reject public v2 envelope")
		check(sim.submit_command(command("pending", "set_time_scale", {"time_scale":5})).accepted, "queue v3 command")
		sim._state.rng.seed = 9223372036854775807
		sim._state.rng.randi()
		sim._state.accumulator_s = 0.375
		var record: Dictionary = sim.export_save()
		var restored = new_sim(with_crew)
		restored.state_changed.connect(func(_s): notifications += 1)
		var before_notice := notifications
		var result: Dictionary = restored.import_save(JSON.parse_string(JSON.stringify(record, "", true, true)))
		check(result.ok, "JSON roundtrip accepted: " + result.get("reason", ""))
		check(notifications == before_notice + 1, "one load notification")
		check(same(sim.export_save(), restored.export_save()), "complete state/journal/RNG roundtrip")
		check(sim._state.rng.randi() == restored._state.rng.randi(), "exact next RNG draw")
		var events: Array = []
		restored.game_event.connect(func(e): events.append(e))
		sim.process_pending_commands()
		restored.process_pending_commands()
		check(events.size() == 1, "pending command resolves once after load")
		check(same(sim.export_save(), restored.export_save()), "same pending resolution")
		for i in 3:
			check(sim.step(1.0).ok and restored.step(1.0).ok, "step restored simulation")
		check(same(sim.export_save(), restored.export_save()), "identical simulation continuation")
		check(restored.submit_command(command("pending", "set_time_scale", {"time_scale":5})).duplicate, "retry deduplicates")
		check(not restored.submit_command(command("pending", "set_time_scale", {"time_scale":20})).accepted, "conflicting retry rejected")
		var saved: Dictionary = restored.export_save()
		var bad := saved.duplicate(true)
		bad.state.records.resources.oxygen_kg.amount = -1
		reject_unchanged(restored, bad, "negative balance")
		bad = saved.duplicate(true)
		bad.state.rng.state = "9223372036854775808"
		reject_unchanged(restored, bad, "overflowed RNG string")
		bad = saved.duplicate(true)
		bad.state.records.buildings.values()[0].definition_id = "missing"
		reject_unchanged(restored, bad, "unknown building")
		bad = saved.duplicate(true)
		bad.state.records.crew.values()[0].health = "wrong"
		reject_unchanged(restored, bad, "malformed crew")
		bad = saved.duplicate(true)
		bad.state.counters.building = 0
		reject_unchanged(restored, bad, "reused allocation counter")
		bad = saved.duplicate(true)
		bad.next_sequence += 1
		reject_unchanged(restored, bad, "sequence gap")
		bad = saved.duplicate(true)
		bad.state.records.campaign.repairs["unimplemented"] = {}
		reject_unchanged(restored, bad, "uninstalled feature partition")
		bad = saved.duplicate(true)
		bad.config.definition_manifest[bad.config.definition_manifest.keys()[0]] = "0".repeat(64)
		reject_unchanged(restored, bad, "definition hash mismatch")
		bad = saved.duplicate(true)
		bad.state.records.clock.elapsed_s = NAN
		reject_unchanged(restored, bad, "non-finite clock")
		bad = saved.duplicate(true)
		bad.state.records.resources.oxygen_kg.amount = {"$f64":"invalid"}
		reject_unchanged(restored, bad, "malformed binary64")
		bad = saved.duplicate(true)
		bad.state.records.resources.oxygen_kg.capacity = 99999
		reject_unchanged(restored, bad, "invented storage capacity")
		bad = saved.duplicate(true)
		bad.state.records.buildings.values()[0].cell = [999, 999]
		reject_unchanged(restored, bad, "invalid footprint")
		bad = saved.duplicate(true)
		bad.save_version = 999
		reject_unchanged(restored, bad, "newer save version")
		check(not new_sim(not with_crew).import_save(saved).ok, "capability mismatch rejected")
		var changed_campaign = new_sim(with_crew, "habitat_6crew_alt")
		check(changed_campaign.import_save(saved).ok, "load another campaign with equal revision")
		check(same(changed_campaign.export_save(), saved), "campaign replaced completely")
		var exposed: Dictionary = restored.export_save()
		exposed.state.records.resources.oxygen_kg.amount = 0
		check(same(saved, restored.export_save()), "export is detached")
		var callback_results: Array = []
		var during_load: Callable = func(_s):
			callback_results.append(restored.export_save())
			callback_results.append(restored.import_save(saved))
		restored.state_changed.connect(during_load)
		check(restored.import_save(saved).ok, "load with callback")
		restored.state_changed.disconnect(during_load)
		check(callback_results.size() == 2 and not callback_results[0].ok and not callback_results[1].ok, "actual load callback cannot recurse or checkpoint")
		restored._busy = true
		check(not restored.export_save().ok and not restored.import_save(saved).ok, "reentrant checkpoint blocked")
		restored._busy = false
	ledger_roundtrip()
	expedition_roundtrip("salvage_6crew")
	expedition_roundtrip("salvage_full_store_6crew")
	storage_roundtrip()
	for failure in failures: print("CAMPAIGN_FOUNDATION_FAIL ", failure)
	print("CAMPAIGN_FOUNDATION_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)

func ledger_roundtrip() -> void:
	var sim = new_sim(true, "salvage_6crew")
	var snapshot: Dictionary = sim.get_snapshot()
	var placed := command("build", "place_building", {"definition_id":"fixture_generator", "cell":[10, 10], "rotation_quarters":0})
	check(sim.submit_command(placed).accepted, "construction accepted")
	sim.process_pending_commands()
	var result: Dictionary = sim._journal.build.result
	check(result.success, "real construction commits: " + result.reason)
	if not result.success: return
	check(not sim._committed_effects.is_empty(), "retained ledger receipt exists")
	var saved: Dictionary = sim.export_save()
	var invalid := saved.duplicate(true)
	invalid.state.prepaid_build_costs.clear()
	reject_unchanged(sim, invalid, "missing construction prepayment")
	var restored = new_sim(true, "salvage_6crew")
	var loaded: Dictionary = restored.import_save(JSON.parse_string(JSON.stringify(saved, "", true, true)))
	check(loaded.ok, "construction/receipt reload: " + loaded.get("reason", ""))
	check(same(saved, restored.export_save()), "prepaid cost and receipt preserved")
	check(restored.submit_command(placed).duplicate, "construction replay deduplicates")
	restored.process_pending_commands()
	check(same(saved, restored.export_save()), "replay does not spend again")
	var cancel := command("cancel", "cancel_task", {"task_id":result.data.task_id})
	restored.submit_command(cancel)
	restored.process_pending_commands()
	check(restored._journal.cancel.result.success, "cancel restored construction")
	check(restored.get_snapshot().resources.alloy.amount == snapshot.resources.alloy.amount, "refund exactly once")
	check(restored.import_save(restored.export_save()).ok, "refund receipt reload")
	var final_save: Dictionary = restored.export_save()
	var fresh = new_sim(true, "salvage_6crew")
	check(fresh.import_save(JSON.parse_string(JSON.stringify(final_save, "", true, true))).ok, "post-refund disk checkpoint")
	for i in 60:
		check(restored.step(1.0).ok and fresh.step(1.0).ok, "post-reload detailed continuation")
	check(same(restored.export_save(), fresh.export_save()), "bit-exact float state after sixty more ticks")

func storage_roundtrip() -> void:
	var sim = new_sim()
	var root := "user://foundation_test_" + str(Time.get_ticks_usec())
	var store := Store.new(root)
	var first_write := store.write(sim)
	check(first_write.ok, "native first save: " + first_write.get("reason", ""))
	if not first_write.ok: return
	sim.step(1.0)
	check(store.write(sim).ok, "native atomic replacement")
	sim.step(1.0)
	check(store.write(sim).ok, "native repeated backup replacement")
	var checkpoint: Dictionary = sim.export_save()
	sim.step(1.0)
	var loaded := store.read(sim, "manual", false)
	check(loaded.ok, "native load accepted: " + loaded.get("reason", ""))
	check(same(sim.export_save(), checkpoint), "native load roundtrip")
	var file := FileAccess.open(root.path_join("manual.json"), FileAccess.WRITE)
	file.store_string("interrupted write")
	file.close()
	var recovery := store.read(sim)
	check(recovery.ok and recovery.get("recovered_backup", false), "corrupt primary recovers previous save")
	check(sim.get_snapshot().clock.tick_index == 1, "backup contains previous checkpoint")
	check(store.write(sim).ok, "replace corrupt primary without copying it over valid backup")
	check(store.valid_checkpoint(ProjectSettings.globalize_path(root.path_join("manual.json.bak")), sim), "valid backup remains after corrupt-primary overwrite")
	var valid_bytes := FileAccess.get_file_as_string(root.path_join("manual.json"))
	sim._state.records.resources.oxygen_kg.amount = -1
	check(not store.write(sim).ok, "invalid live state cannot replace a good checkpoint")
	check(FileAccess.get_file_as_string(root.path_join("manual.json")) == valid_bytes, "invalid save leaves prior bytes intact")
	check(store.read(sim, "manual", false).ok, "restore after invalid live state")
	check(not store.write(sim, "../escape").ok, "slot traversal rejected")
	for i in 3: check(store.autosave(sim).ok, "rotating autosave")
	for i in 3: check(FileAccess.file_exists(root.path_join("auto_%d.json" % i)), "three autosaves retained")
	# Remove only the files created by this unique test instance.
	var dir := DirAccess.open(root)
	for name in dir.get_files(): DirAccess.remove_absolute(ProjectSettings.globalize_path(root.path_join(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(root))

func expedition_roundtrip(preset: String) -> void:
	var sim = new_sim(true, preset)
	var launch := command("launch", "start_eva", {"site_id":"site_cargo_a", "crew_ids":["crew_000001", "crew_000002"], "work_duration_s":2.0, "oxygen_kg_per_crew":0.12, "battery_kwh_per_crew":0.006})
	check(sim.submit_command(launch).accepted, "expedition queued " + preset)
	sim.process_pending_commands()
	check(sim._journal.launch.result.success, "expedition launched " + preset)
	if not sim._journal.launch.result.success: return
	var trip_id: String = sim._journal.launch.result.data.expedition_id
	var restored = new_sim(true, preset)
	var seen := {}
	var completed := false
	for i in 100:
		var status: String = sim.get_snapshot().expeditions[trip_id].status
		if not seen.has(status):
			seen[status] = true
			var saved: Dictionary = sim.export_save()
			var loaded: Dictionary = restored.import_save(JSON.parse_string(JSON.stringify(saved, "", true, true)))
			check(loaded.ok, "expedition checkpoint " + status + " " + loaded.get("reason", ""))
			check(same(saved, restored.export_save()), "exact route/suit/cargo/cache checkpoint " + status)
		if status == "completed":
			completed = true
			break
		check(sim.step(1.0).ok and restored.step(1.0).ok, "expedition step after reload")
		check(same(sim.export_save(), restored.export_save()), "identical expedition continuation")
	check(completed, "expedition returned " + preset)
	check(seen.has("outbound") and seen.has("working") and seen.has("returning"), "checkpoint each active expedition phase")
	if preset == "salvage_full_store_6crew": check(not sim._state.return_caches.is_empty(), "overflow cargo retained across checkpoint")
