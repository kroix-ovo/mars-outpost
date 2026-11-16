extends RefCounted
## Complete boundary checkpoint codec. Decode never touches a live simulation.
const Campaign = preload("res://scripts/campaign/campaign_schema.gd")
const Schema = preload("res://scripts/simulation/command_schemas.gd")
const State = preload("res://scripts/simulation/game_state.gd")
const Definitions = preload("res://scripts/simulation/definitions.gd")
const Ledger = preload("res://scripts/simulation/resource_ledger.gd")
const Adapter = preload("res://scripts/crew/crew_adapter.gd")
const Record = preload("res://scripts/crew/crew_save_record.gd")
const Commands = preload("res://scripts/campaign/campaign_commands.gd")
const STATE_FIELDS = ["records", "accumulator_s", "counters", "per_battery_energy", "return_caches",
	"prepaid_build_costs", "power_flows", "life_support_flows", "crew_demand", "rng"]
const ENVELOPE = ["format", "save_version", "contract_version", "rng_algorithm", "godot_version",
	"campaign_content_sha256", "config", "state", "has_crew_adapter", "journal", "pending", "next_sequence", "effects"]

static func encode(sim: RefCounted) -> Dictionary:
	var s: RefCounted = sim._state
	var packed := {}
	for key in STATE_FIELDS:
		if key == "rng": packed[key] = {"seed": str(s.rng.seed), "state": str(s.rng.state)}
		else:
			var value: Variant = s.get(key)
			packed[key] = value.duplicate(true) if value is Dictionary else value
	var envelope := {"format": "mars-outpost-campaign", "save_version": Campaign.SAVE_VERSION,
		"contract_version": Campaign.VERSION, "rng_algorithm": "godot-random-number-generator",
		"godot_version": Engine.get_version_info().hex,
		"campaign_content_sha256": FileAccess.get_sha256(Campaign.CONTENT),
		"config": sim._config.duplicate(true), "state": packed, "has_crew_adapter": sim._crew_adapter != null,
		"journal": sim._journal.duplicate(true), "pending": Array(sim._pending),
		"next_sequence": sim._next_receive_sequence, "effects": sim._committed_effects.duplicate(true)}
	# Godot's JSON decimal parser can move a float by one ULP. Store binary64 bytes
	# explicitly so a disk checkpoint resumes the exact deterministic simulation.
	return pack_floats(envelope)

static func decode(save: Dictionary, world: RefCounted, wants_adapter: bool, kinds: Dictionary = {}) -> Dictionary:
	if not Schema.exact_keys(save, ENVELOPE): return fail("Invalid campaign save envelope.")
	if save.format != "mars-outpost-campaign" or save.save_version != Campaign.SAVE_VERSION or save.contract_version != Campaign.VERSION:
		return fail("Unsupported campaign save version.", "incompatible_save")
	if save.rng_algorithm != "godot-random-number-generator" or save.godot_version != Engine.get_version_info().hex:
		return fail("RNG continuation requires the same Godot version.", "incompatible_save")
	if save.campaign_content_sha256 != FileAccess.get_sha256(Campaign.CONTENT): return fail("Campaign content changed.", "definition_mismatch")
	if not finite_tree(save): return fail("Non-finite or unsupported value in save data.")
	if not save.config is Dictionary or not save.state is Dictionary:
		return fail("Malformed save config/state.")
	var unpacked: Variant = unpack_floats(save)
	if not finite_tree(unpacked): return fail("Malformed binary64 value.")
	save = unpacked
	if not save.has_crew_adapter is bool or save.has_crew_adapter != wants_adapter: return fail("Crew capability differs from this session.", "incompatible_save")
	var loaded_profile: Dictionary = Campaign.load_profile(save.config)
	if not loaded_profile.ok: return loaded_profile
	var profile: Dictionary = loaded_profile.profile
	var core_config: Dictionary = Campaign.base_config(save.config)
	var content: Dictionary = Definitions.new().load_config(core_config)
	if not content.ok: return content
	if world != null and (world.map.id != save.config.map_id or world.map.revision != save.config.map_revision):
		return fail("Load the checkpoint's world before importing it.", "definition_mismatch")
	if world != null:
		for id in content.buildings:
			if Campaign.canonical(world.definitions.get_definition(id)) != Campaign.canonical(content.buildings[id]):
				return fail("World and checkpoint building definitions differ.", "definition_mismatch")
	var packed: Dictionary = save.state
	if not Schema.exact_keys(packed, STATE_FIELDS): return fail("Invalid authoritative state fields.")
	if not packed.rng is Dictionary or not Schema.exact_keys(packed.rng, ["seed", "state"]) or not decimal64(packed.rng.seed, false) or not decimal64(packed.rng.state, true):
		return fail("RNG seed/state must be exact int64 decimal strings.")
	if not Schema.number(packed.accumulator_s) or packed.accumulator_s < 0 or packed.accumulator_s > Schema.MAX_EXACT_INTEGER:
		return fail("Invalid fractional clock accumulator.")
	for key in STATE_FIELDS:
		if key != "accumulator_s" and not packed[key] is Dictionary: return fail("State field must be an object: " + key)
	var candidate = State.new()
	candidate.populate(core_config, content)
	var template: Dictionary = candidate.records.duplicate(true)
	template.contract_version = Campaign.VERSION
	template.snapshot_version = Campaign.SNAPSHOT_VERSION
	template.campaign = Campaign.initial(template.crew, template.crew.keys()[0])
	# Development-save policy: a foundation (partition schema 1) checkpoint gains the
	# default time record for its own tick. Nothing else is invented or erased.
	var migrated_from: Variant = null
	if packed.records.get("campaign") is Dictionary and packed.records.campaign.get("schema_version") == 1 and packed.records.get("clock") is Dictionary and Schema.whole(packed.records.clock.get("tick_index")):
		var upgraded: Variant = Campaign.migrate(packed.records.campaign, int(packed.records.clock.tick_index), profile)
		if upgraded is Dictionary and upgraded.get("schema_version") == Campaign.PARTITION_VERSION:
			packed = packed.duplicate(true)
			packed.records.campaign = upgraded
			migrated_from = 1
	var valid := validate_records(packed.records, template, content, profile, kinds)
	if not valid.ok: return valid
	for key in STATE_FIELDS:
		if key != "rng": candidate.set(key, packed[key].duplicate(true) if packed[key] is Dictionary else float(packed[key]))
	candidate.rng.seed = int(packed.rng.seed)
	candidate.rng.state = int(packed.rng.state)
	valid = validate_counters(candidate)
	if not valid.ok: return valid
	valid = validate_auxiliary(candidate, content)
	if not valid.ok: return valid
	var adapter: RefCounted = null
	if wants_adapter:
		if world == null: return fail("Crew gameplay requires a world.")
		adapter = Adapter.new(world)
		valid = adapter.initialize(save.config, candidate.snapshot())
		if not valid.ok: return valid
	var partition := {"schema_version": 1, "state": {"crew": candidate.records.crew, "tasks": candidate.records.tasks,
		"expeditions": candidate.records.expeditions, "return_caches": candidate.return_caches, "completion_markers": {}, "private_counters": {}}}
	valid = Record.validate(partition, candidate.snapshot(), content.crew)
	if not valid.ok: return valid
	for b in candidate.records.buildings.values():
		if b.lifecycle == "constructing":
			var task: Dictionary = candidate.records.tasks[b.construction_task_id]
			if task.kind != "construct" or task.status in ["completed", "cancelled", "failed"] or not candidate.prepaid_build_costs.has(task.id):
				return fail("Constructing building lacks its prepaid active job.")
	valid = Ledger.new(candidate, content, {}, candidate.records.clock.tick_index).validate()
	if not valid.ok: return valid
	valid = validate_journal(save, candidate)
	if not valid.ok: return valid
	valid = validate_effects(save.effects, candidate.records.clock.tick_index)
	if not valid.ok: return valid
	return {"ok": true, "state": candidate, "content": content, "config": save.config.duplicate(true),
		"profile": profile, "migrated_from": migrated_from,
		"adapter": adapter, "journal": save.journal.duplicate(true), "pending": save.pending.duplicate(),
		"next_sequence": int(save.next_sequence), "effects": save.effects.duplicate(true)}

static func validate_records(r: Dictionary, template: Dictionary, content: Dictionary, profile: Dictionary = Campaign.LEGACY_PROFILE, kinds: Dictionary = {}) -> Dictionary:
	if not Schema.exact_keys(r, template.keys()): return fail("Invalid snapshot keys.")
	for key in template:
		if template[key] is Dictionary and not r[key] is Dictionary: return fail("Invalid collection: " + key)
	if r.contract_version != Campaign.VERSION or r.snapshot_version != Campaign.SNAPSHOT_VERSION or r.campaign_id != template.campaign_id:
		return fail("Campaign identity/version differs from its initialization.")
	if not Schema.whole(r.revision) or Campaign.canonical(r.map) != Campaign.canonical(template.map): return fail("Invalid revision or map.")
	if not Schema.exact_keys(r.clock, ["tick_index", "elapsed_s", "time_scale"]) or not Schema.whole(r.clock.tick_index) or r.clock.elapsed_s != r.clock.tick_index or r.clock.time_scale not in [0, 1, 5, 20]:
		return fail("Invalid clock.")
	if not Schema.exact_keys(r.resources, template.resources.keys()): return fail("Resource registry mismatch.")
	for id in r.resources:
		var b: Variant = r.resources[id]
		if not b is Dictionary or not Schema.exact_keys(b, template.resources[id].keys()): return fail("Invalid resource fields.")
		if b.id != id or not Schema.number(b.net_rate_per_s) or (b.forecast_empty_s != null and (not Schema.number(b.forecast_empty_s) or b.forecast_empty_s < 0)):
			return fail("Invalid resource diagnostics.")
	if not Schema.exact_keys(r.power, template.power.keys()): return fail("Invalid power summary.")
	for value in r.power.values():
		if not Schema.number(value) or value < 0: return fail("Invalid power value.")
	var building_fields := ["id", "definition_id", "cell", "rotation_quarters", "lifecycle", "enabled", "condition", "construction_task_id", "construction_progress", "power_requested_kw", "power_served_kw", "operating_fraction", "blocking_codes"]
	var occupied := {}
	for id in r.buildings:
		var b: Variant = r.buildings[id]
		if not b is Dictionary or not Schema.exact_keys(b, building_fields): return fail("Invalid building fields.")
		if b.id != id or not content.buildings.has(b.definition_id) or not Schema.cell(b.cell) or not Schema.whole(b.rotation_quarters, 0, 3) or not b.enabled is bool:
			return fail("Invalid building definition or placement.")
		if b.lifecycle not in ["constructing", "commissioned"] or not fraction(b.condition) or not fraction(b.construction_progress) or not fraction(b.operating_fraction): return fail("Invalid building lifecycle.")
		if b.lifecycle == "commissioned" and b.construction_progress != 1.0: return fail("Commissioned building has incomplete construction.")
		for key in ["power_requested_kw", "power_served_kw"]:
			if not Schema.number(b[key]) or b[key] < 0: return fail("Invalid building power.")
		if not b.blocking_codes is Array: return fail("Invalid building blockers.")
		for code in b.blocking_codes:
			if not Schema.identifier(code): return fail("Invalid blocking code.")
		if b.construction_task_id != null and (not r.tasks.has(b.construction_task_id) or not r.tasks[b.construction_task_id] is Dictionary or r.tasks[b.construction_task_id].get("target_id") != id): return fail("Missing construction task.")
		if (b.lifecycle == "constructing") != (b.construction_task_id != null): return fail("Construction link inconsistent.")
		for offset in content.buildings[b.definition_id].footprint_cells:
			var cell := Vector2i(int(offset[0]), int(offset[1]))
			for turn in int(b.rotation_quarters): cell = Vector2i(-cell.y, cell.x)
			cell += Vector2i(int(b.cell[0]), int(b.cell[1]))
			if cell.x < 0 or cell.y < 0 or cell.x >= content.map.size_cells[0] or cell.y >= content.map.size_cells[1] or occupied.has(str(cell)):
				return fail("Building footprint out of bounds or overlapping.")
			occupied[str(cell)] = id
	for id in r.resources:
		if id == "energy_kwh" or r.resources[id].capacity == null: continue
		var expected_capacity: float = content.scenario.starting_storage_capacity.get(id, 0.0)
		for b in r.buildings.values():
			if b.lifecycle == "commissioned": expected_capacity += content.buildings[b.definition_id].storage_capacity.get(id, 0.0)
		if r.resources[id].capacity != expected_capacity: return fail("Storage capacity differs from commissioned equipment.")
	if not Schema.exact_keys(r.sites, template.sites.keys()): return fail("Site identities changed.")
	for id in r.sites:
		var site: Variant = r.sites[id]
		if not site is Dictionary or not Schema.exact_keys(site, template.sites[id].keys()): return fail("Invalid site.")
		for key in ["id", "definition_id", "cell"]:
			if site[key] != template.sites[id][key]: return fail("Site geometry/definition changed.")
		if not site.remaining_cargo is Dictionary: return fail("Invalid site cargo.")
	if not r.alerts is Array: return fail("Invalid alerts.")
	var alert_ids := {}
	for alert in r.alerts:
		if not alert is Dictionary or not Schema.exact_keys(alert, ["id", "code", "message", "severity", "entity_ids", "first_tick"]): return fail("Malformed alert.")
		if not Schema.identifier(alert.id) or alert_ids.has(alert.id) or not Schema.identifier(alert.code) or not alert.message is String or alert.severity not in ["warning", "critical", "info"] or not alert.entity_ids is Array or not Schema.whole(alert.first_tick, 0, r.clock.tick_index): return fail("Invalid alert fields.")
		for entity in alert.entity_ids:
			if not Schema.identifier(entity): return fail("Invalid alert entity.")
		alert_ids[alert.id] = true
	if not r.active_events.is_empty() or Campaign.canonical(r.technology) != Campaign.canonical(template.technology): return fail("Event/research handlers not installed.")
	return Campaign.validate(r.campaign, r.crew, int(r.clock.tick_index), profile, kinds)

static func validate_counters(s: RefCounted) -> Dictionary:
	if not Schema.exact_keys(s.counters, ["building", "crew", "task", "expedition", "event"]): return fail("Invalid entity counters.")
	for kind in s.counters:
		if not Schema.whole(s.counters[kind]): return fail("Invalid entity counter.")
		var collection: Dictionary = s.records.get({"building":"buildings", "crew":"crew", "task":"tasks", "expedition":"expeditions", "event":"active_events"}[kind], {})
		for id in collection:
			if not id is String or not id.begins_with(kind + "_"): return fail("Invalid allocated ID.")
			var suffix: String = id.trim_prefix(kind + "_")
			if not suffix.is_valid_int() or int(suffix) < 1 or int(suffix) > s.counters[kind] or id != "%s_%06d" % [kind, int(suffix)]: return fail("Counter would reuse an allocated ID.")
	return good()

static func validate_auxiliary(s: RefCounted, content: Dictionary) -> Dictionary:
	if not Schema.exact_keys(s.crew_demand, ["requested", "provided", "unmet_needs", "flows", "wastewater_overflow_kg"]): return fail("Invalid crew demand fields.")
	for key in ["requested", "provided", "unmet_needs", "flows"]:
		if not s.crew_demand[key] is Dictionary: return fail("Invalid demand collection.")
	if not Schema.number(s.crew_demand.wastewater_overflow_kg) or s.crew_demand.wastewater_overflow_kg < 0: return fail("Invalid overflow.")
	for key in ["requested", "provided", "unmet_needs"]:
		for id in s.crew_demand[key]:
			if not s.records.crew.has(id): return fail("Demand references unknown crew.")
			var item: Variant = s.crew_demand[key][id]
			if key == "unmet_needs":
				if not item is Array: return fail("Invalid unmet needs.")
				for code in item:
					if code not in ["oxygen", "water", "food", "suit_energy"]: return fail("Unknown unmet need.")
			else:
				if not item is Dictionary: return fail("Invalid demand map.")
				for rid in item:
					if rid not in ["oxygen_kg", "potable_water_kg", "food_kcal", "energy_kwh"] or not Schema.number(item[rid]) or item[rid] < 0: return fail("Invalid demand quantity.")
	for key in ["power_flows", "life_support_flows"]:
		for q in s.get(key).values():
			if not Schema.number(q) or q < 0: return fail("Invalid diagnostic flow.")
	for id in s.prepaid_build_costs:
		if not s.records.tasks.has(id) or not s.records.tasks[id] is Dictionary or s.records.tasks[id].get("kind") != "construct": return fail("Invalid prepaid construction owner.")
		var task: Dictionary = s.records.tasks[id]
		if not s.records.buildings.has(task.get("target_id")): return fail("Missing prepaid building.")
		var cost: Variant = s.prepaid_build_costs[id]
		if not cost is Dictionary or Campaign.canonical(cost) != Campaign.canonical(content.buildings[s.records.buildings[task.target_id].definition_id].build_cost): return fail("Prepaid cost mismatch.")
	return good()

static func validate_journal(save: Dictionary, s: RefCounted) -> Dictionary:
	if not save.journal is Dictionary or not save.pending is Array or not Schema.whole(save.next_sequence, 1): return fail("Invalid command queue.")
	var sequences := {}
	var queued := {}
	for id in save.journal:
		var entry: Variant = save.journal[id]
		if not Schema.identifier(id) or not entry is Dictionary or not Schema.exact_keys(entry, ["normalized", "receive_sequence", "status", "result"]): return fail("Invalid journal entry.")
		if not entry.normalized is Dictionary: return fail("Invalid normalized command.")
		# Commands that exist only in 3.0.0 are journaled as validated v3 envelopes.
		var command: Dictionary = Commands.validate(entry.normalized) if Commands.owns(entry.normalized.get("type")) else Schema.validate(entry.normalized)
		if not command.ok or entry.normalized.command_id != id or Campaign.canonical(command.command) != Campaign.canonical(entry.normalized): return fail("Invalid normalized command.")
		if not Schema.whole(entry.receive_sequence, 1, save.next_sequence - 1) or sequences.has(entry.receive_sequence): return fail("Duplicate/out-of-range receive sequence.")
		sequences[entry.receive_sequence] = true
		if entry.status == "queued":
			if entry.result != null: return fail("Queued command has a result.")
			queued[id] = entry.receive_sequence
		elif entry.status == "resolved":
			var result: Variant = entry.result
			if not result is Dictionary or not Schema.exact_keys(result, ["success", "code", "reason", "resolved_tick", "data"]): return fail("Invalid command result.")
			if not result.success is bool or not Schema.identifier(result.code) or not result.reason is String or not result.data is Dictionary or not Schema.whole(result.resolved_tick, 0, s.records.clock.tick_index): return fail("Invalid command result values.")
		else: return fail("Unknown journal status.")
	if save.next_sequence != save.journal.size() + 1: return fail("Receive sequence contains a gap.")
	if queued.size() != save.pending.size(): return fail("Pending/journal mismatch.")
	var last := 0
	for id in save.pending:
		if not id is String or not queued.has(id) or queued[id] <= last: return fail("Pending commands are duplicated or out of order.")
		last = int(queued[id])
	return good()

static func validate_effects(effects: Variant, tick: int) -> Dictionary:
	if not effects is Dictionary: return fail("Invalid effect receipts.")
	for id in effects:
		var receipt: Variant = effects[id]
		if not Schema.identifier(id) or id.begins_with("tick:") or not receipt is Dictionary or not Schema.exact_keys(receipt, ["fingerprint", "result"]): return fail("Invalid retained receipt.")
		if not receipt.fingerprint is String or not receipt.result is Dictionary: return fail("Invalid receipt fields.")
		var fingerprint: Variant = JSON.parse_string(receipt.fingerprint)
		if not fingerprint is Dictionary or not Schema.exact_keys(fingerprint, ["trusted", "effect"]) or not fingerprint.trusted is bool or not fingerprint.effect is Dictionary: return fail("Malformed effect fingerprint.")
		var effect: Dictionary = fingerprint.effect
		if not Schema.exact_keys(effect, ["effect_id", "kind", "owner_id", "scope", "debits", "credits"]) or effect.effect_id != id or effect.scope != "one_time" or not Schema.identifier(effect.owner_id) or not effect.debits is Dictionary or not effect.credits is Dictionary: return fail("Malformed retained effect.")
		var result: Dictionary = receipt.result
		if not Schema.exact_keys(result, ["ok", "code", "reason", "applied_tick", "flows"]) or result.ok != true or result.code != "ok" or result.reason != "" or not Schema.whole(result.applied_tick, 0, tick) or not result.flows is Dictionary: return fail("Malformed receipt result.")
		for side in ["debits", "credits"]:
			for path in effect[side]:
				if not Schema.identifier(path) or not Schema.number(effect[side][path]) or effect[side][path] < 0: return fail("Invalid effect quantity.")
		for q in result.flows.values():
			if not Schema.number(q) or q < 0: return fail("Invalid receipt flow.")
	return good()

static func finite_tree(value: Variant, depth: int = 0) -> bool:
	if depth > 64: return false
	if value is float: return is_finite(value)
	if value is Dictionary:
		for key in value:
			if not key is String or not finite_tree(value[key], depth + 1): return false
	elif value is Array:
		for item in value:
			if not finite_tree(item, depth + 1): return false
	elif value != null and not (value is int or value is bool or value is String): return false
	return true

static func decimal64(value: Variant, signed: bool) -> bool:
	if not value is String or not value.is_valid_int(): return false
	if str(int(value)) != value: return false
	return signed or int(value) >= 0

static func pack_floats(value: Variant) -> Variant:
	if value is float:
		var bytes := PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0, value)
		return {"$f64": bytes.hex_encode()}
	if value is Dictionary:
		var result := {}
		for key in value:
			var name: Variant = String(key) if key is StringName else key
			result[name] = pack_floats(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(pack_floats(item))
		return result
	return value

static func unpack_floats(value: Variant) -> Variant:
	# Untagged numbers were integer fields before JSON parsing. Tagged values
	# return directly above this recursion, preserving their floating-point type.
	if value is float and is_finite(value) and absf(value) <= Schema.MAX_EXACT_INTEGER and value == floorf(value): return int(value)
	if value is Dictionary:
		if value.has("$f64"):
			var hex: Variant = value["$f64"]
			if value.size() != 1 or not hex is String or hex.length() != 16 or not hex.is_valid_hex_number(false): return NAN
			return hex.hex_decode().decode_double(0)
		var result := {}
		for key in value: result[key] = unpack_floats(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(unpack_floats(item))
		return result
	return value

static func fraction(value: Variant) -> bool:
	return Schema.number(value) and value >= 0.0 and value <= 1.0

static func good() -> Dictionary:
	return {"ok": true, "code": "ok", "reason": ""}

static func fail(reason: String, code: String = "invalid_save") -> Dictionary:
	return {"ok": false, "code": code, "reason": reason}
