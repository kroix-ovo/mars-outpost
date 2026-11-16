extends RefCounted
## Campaign v3 foundation. Later packages version their own populated partitions.
const VERSION := "3.0.0"
const SNAPSHOT_VERSION := 3
const SAVE_VERSION := 3
const CONTENT := "res://data/campaign/content.json"
const Schema = preload("res://scripts/simulation/command_schemas.gd")
const Scheduler = preload("res://scripts/campaign/campaign_scheduler.gd")
const PARTITION_VERSION := 2
const PROFILE_KEY := "campaign_profile_path"
## Without a campaign profile the facade keeps fixture clock semantics: one simulated
## second per real second and multiplier, running at start, at most 120 ticks per call.
const LEGACY_PROFILE = {"id": "fixture_legacy", "base_rate_sim_s_per_real_s": 1, "player_multipliers": [1, 5, 20],
	"start_time_scale": 1, "owns_time_pacing": false, "max_ticks_per_advance": 120,
	"max_detailed_ticks_per_advance": 120, "max_aggregate_account_ticks_per_advance": 200000,
	"guard_ticks": 2, "min_aggregate_ticks": 4}

static func load_profile(config: Dictionary) -> Dictionary:
	## The optional profile is hash-verified through the same manifest as other content.
	if not config.has(PROFILE_KEY): return {"ok": true, "profile": LEGACY_PROFILE.duplicate(true)}
	var path: Variant = config[PROFILE_KEY]
	var manifest: Variant = config.get("definition_manifest")
	if not path is String or not manifest is Dictionary or not manifest.has(path) or not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != manifest[path]:
		return {"ok": false, "code": "definition_mismatch", "reason": "Campaign time profile is absent from the manifest or changed."}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var keys := LEGACY_PROFILE.keys() + ["schema_version", "metadata"]
	if not data is Dictionary or not Schema.exact_keys(data, keys) or data.schema_version != 1 or not Schema.identifier(data.id) or data.id == LEGACY_PROFILE.id or not data.metadata is Dictionary:
		return {"ok": false, "code": "invalid_schema", "reason": "Invalid campaign time profile."}
	var profile: Dictionary = normalized(data)
	if not Schema.whole(profile.base_rate_sim_s_per_real_s, 1, 3600) or profile.player_multipliers != [1, 5, 20] or profile.start_time_scale not in [0, 1, 5, 20] or not profile.owns_time_pacing is bool:
		return {"ok": false, "code": "invalid_value", "reason": "Invalid campaign pacing."}
	# Zero means no total-tick cap; work is then bounded by the two budgets below.
	if not Schema.whole(profile.max_ticks_per_advance) or not Schema.whole(profile.max_detailed_ticks_per_advance, 2, 120) or not Schema.whole(profile.max_aggregate_account_ticks_per_advance, 1, 100000000) or not Schema.whole(profile.guard_ticks, 1, 3600) or not Schema.whole(profile.min_aggregate_ticks, 3, 3600):
		return {"ok": false, "code": "invalid_value", "reason": "Invalid campaign frame budgets."}
	profile.erase("schema_version")
	profile.erase("metadata")
	return {"ok": true, "profile": profile}

static func base_config(config: Dictionary) -> Dictionary:
	## The v2 loader accepts only its own keys; the campaign key is consumed here.
	var result := config.duplicate(true)
	result.erase(PROFILE_KEY)
	return result

static func migrate(value: Variant, tick: int, profile: Dictionary) -> Variant:
	## Explicit development-save migration. Foundation (schema 1) partitions had no
	## time record; add the deterministic default for the checkpoint's own tick.
	if not value is Dictionary or value.get("schema_version") != 1 or value.has("time") or not value.get("calendar") is Dictionary: return value
	var calendar: Dictionary = value.calendar
	for key in ["day_seconds", "month_days", "shipment_days", "campaign_days"]:
		if not Schema.whole(calendar.get(key), 1): return value
	var migrated: Dictionary = value.duplicate(true)
	migrated.schema_version = PARTITION_VERSION
	migrated.time = Scheduler.initial_time(normalized(calendar), tick, profile)
	return migrated

static func initial(crew: Dictionary, commander_id: String, profile: Dictionary = LEGACY_PROFILE, tick: int = 0) -> Dictionary:
	var calendar := {"day_seconds": 86400, "month_days": 30, "shipment_days": 180, "campaign_days": 720}
	return {
		"schema_version": PARTITION_VERSION, "commander_id": commander_id,
		"time": Scheduler.initial_time(calendar, tick, profile),
		"calendar": {"day_seconds": 86400, "month_days": 30, "shipment_days": 180, "campaign_days": 720},
		"camp_level": 0, "research_points": 0.0, "unlocked_research": [],
		"zones": {}, "crew_needs": {}, "schedules": {}, "medical": {}, "maintenance": {},
		"repairs": {}, "crops": {}, "upgrades": {}, "discoveries": {},
		"cargo": {"next_arrival_s": 15552000, "delivered_cycles": [], "manifest": [], "unloading": {}},
		"director": {"next_check_s": 86400, "cooldowns": {}, "history": []},
		"tutorial": {"stage": "arrival", "completed_ids": [], "active": true},
		"standing_orders": {"commander_meals": true, "commander_sleep": true}
	}

static func validate(value: Variant, crew: Dictionary, tick: int = 0, profile: Dictionary = LEGACY_PROFILE, kinds: Dictionary = {}) -> Dictionary:
	if not value is Dictionary: return invalid("Campaign partition must be an object.")
	var template := initial(crew, "")
	if not Schema.exact_keys(value, template.keys()) or value.schema_version != PARTITION_VERSION:
		return invalid("Unsupported campaign partition shape/version.")
	if not value.commander_id is String or not crew.has(value.commander_id): return invalid("Missing commander.")
	if not Schema.whole(value.camp_level, 0, 5) or not Schema.number(value.research_points) or value.research_points < 0:
		return invalid("Invalid camp progression.")
	for key in ["zones", "crew_needs", "schedules", "medical", "maintenance", "repairs", "crops", "upgrades", "discoveries"]:
		# Package 1 does not claim to validate or implement future populated schemas.
		if not value[key] is Dictionary or not value[key].is_empty(): return invalid("Partition requires its feature package: " + key)
	if not value.calendar is Dictionary or canonical(value.calendar) != canonical(template.calendar):
		return invalid("Unsupported campaign calendar.")
	if not value.unlocked_research is Array or not value.unlocked_research.is_empty(): return invalid("Research handler not installed.")
	for key in ["cargo", "director", "tutorial", "standing_orders"]:
		if not value[key] is Dictionary or canonical(value[key]) != canonical(template[key]):
			return invalid("Partition requires its feature package: " + key)
	var known := kinds.duplicate()
	for kind in Scheduler.BUILTIN: known[kind] = null
	return Scheduler.validate(value.time, template.calendar, tick, profile, known)

static func invalid(reason: String) -> Dictionary:
	return {"ok": false, "code": "invalid_save", "reason": reason}

static func normalized(value: Variant) -> Variant:
	# JSON parses numbers as floats; only exactly representable whole values become ints.
	if value is float and is_finite(value) and absf(value) <= Schema.MAX_EXACT_INTEGER and value == floorf(value): return int(value)
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = normalized(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(normalized(item))
		return result
	return value

static func canonical(value: Variant) -> String:
	return JSON.stringify(normalized(value), "", true, true)
