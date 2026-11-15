extends RefCounted
## Validate a detached candidate. Never repairs a malformed save in place.

const MAX_INTEGER := 9007199254740991
const KEYS := ["crew", "tasks", "expeditions", "return_caches", "completion_markers", "private_counters"]
const CREW_FIELDS := ["id", "definition_id", "display_name", "status", "location_kind", "position_m",
	"task_id", "expedition_id", "health", "fatigue", "stress", "radiation_dose_msv", "skills"]
const TASK_FIELDS := ["id", "kind", "target_id", "status", "priority", "crew_required", "assigned_crew_ids",
	"required_work_s", "completed_work_s", "blocked_code", "expedition_id"]
const EVA_FIELDS := ["id", "site_id", "task_id", "crew_ids", "status", "route_id", "route_waypoints_m",
	"route_distance_m", "route_progress_m", "work_required_s", "work_completed_s", "suit_stores",
	"cargo", "return_margin_s", "recall_requested"]
const TERMINAL_TASK := ["completed", "failed", "cancelled"]
const TERMINAL_EVA := ["completed", "failed"]

static func number(v: Variant, minimum: float = -INF, maximum: float = INF) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v >= minimum and v <= maximum

static func whole(v: Variant, minimum: int, maximum: int = MAX_INTEGER) -> bool:
	return number(v, minimum, maximum) and float(v) == floorf(float(v))

static func fields(item: Variant, expected: Array) -> bool:
	return item is Dictionary and item.size() == expected.size() and item.has_all(expected)

static func name_is_valid(item: Variant) -> bool:
	return item is String and not item.is_empty()

static func nullable_id(item: Variant) -> bool:
	return item == null or name_is_valid(item)

static func point(item: Variant) -> bool:
	return item is Array and item.size() == 3 and number(item[0]) and number(item[1]) and number(item[2])

static func amounts(value: Variant, resources: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	for id in value:
		if not resources.has(id) or not number(value[id], 0.0):
			return false
		if resources[id].unit == "count" and not whole(value[id], 0):
			return false
	return true

static func ids(value: Variant, records: Dictionary) -> bool:
	if not value is Array:
		return false
	var seen := {}
	for id in value:
		if not name_is_valid(id) or seen.has(id) or not records.has(id):
			return false
		seen[id] = true
	return true

static func invalid(detail: String) -> Dictionary:
	return {"ok": false, "code": "invalid_save", "reason": detail}

static func validate(record: Dictionary, core: Dictionary, definitions: Dictionary) -> Dictionary:
	if not fields(record, ["schema_version", "state"]) or not fields(record.state, KEYS):
		return invalid("Invalid crew_tasks envelope or partition.")
	if not whole(record.schema_version, 1, 1):
		return {"ok": false, "code": "incompatible_save", "reason": "Unsupported crew_tasks schema."}
	var s: Dictionary = record.state
	for key in KEYS:
		if not s[key] is Dictionary:
			return invalid("Expected a dictionary for " + key)
	if s.crew.size() < 5 or s.crew.size() > 9:
		return invalid("Unexpected crew roster size.")
	var buildings: Dictionary = core.get("buildings", {})
	var sites: Dictionary = core.get("sites", {})
	var resources: Dictionary = core.get("resources", {})

	for id in s.crew:
		var c: Variant = s.crew[id]
		if not fields(c, CREW_FIELDS) or not name_is_valid(id) or c.id != id \
				or not definitions.has(c.definition_id) or not name_is_valid(c.display_name) \
				or c.status not in ["idle", "working", "travelling", "eva", "incapacitated", "dead"] \
				or c.location_kind not in ["base", "eva"] or not point(c.position_m) \
				or not nullable_id(c.task_id) or not nullable_id(c.expedition_id) \
				or not number(c.health, 0.0, 1.0) or not number(c.fatigue, 0.0, 1.0) \
				or not number(c.stress, 0.0, 1.0) or not number(c.radiation_dose_msv, 0.0) \
				or not c.skills is Dictionary:
			return invalid("Invalid crew record: " + str(id))
		for skill in c.skills:
			if not name_is_valid(skill) or not number(c.skills[skill], 0.0, 1.0):
				return invalid("Invalid skill on " + id)
		if c.location_kind == "eva":
			if not s.expeditions.has(c.expedition_id) or not s.tasks.has(c.task_id) \
					or c.status not in ["eva", "incapacitated", "dead"]:
				return invalid("Missing EVA links: " + id)
		elif c.expedition_id != null or c.status == "eva":
			return invalid("Base crew has an EVA link: " + id)
		if c.task_id != null and not s.tasks.has(c.task_id):
			return invalid("Crew references missing task: " + id)
		if c.status in ["travelling", "working"] and c.task_id == null:
			return invalid("Working crew has no task: " + id)

	for id in s.tasks:
		var t: Variant = s.tasks[id]
		if not fields(t, TASK_FIELDS) or not name_is_valid(id) or t.id != id \
				or t.kind not in ["construct", "farm", "repair", "eva"] \
				or t.status not in ["queued", "active", "blocked", "completed", "cancelled", "failed"] \
				or not whole(t.priority, 0, 100) or not whole(t.crew_required, 1, 9) \
				or not ids(t.assigned_crew_ids, s.crew) or t.assigned_crew_ids.size() > t.crew_required \
				or not number(t.required_work_s, 0.0) or not number(t.completed_work_s, 0.0, t.required_work_s) \
				or not nullable_id(t.blocked_code) or not nullable_id(t.expedition_id) or not name_is_valid(t.target_id):
			return invalid("Invalid task record: " + str(id))
		if t.kind == "eva":
			if not s.expeditions.has(t.expedition_id) or not sites.has(t.target_id):
				return invalid("Missing EVA task links: " + id)
		elif t.expedition_id != null or (not buildings.has(t.target_id) and t.status not in TERMINAL_TASK):
			return invalid("Missing or incompatible building task target: " + id)
		if t.status not in TERMINAL_TASK:
			for cid in t.assigned_crew_ids:
				if s.crew[cid].task_id != id:
					return invalid("Crew assignment mismatch: " + id)
	for id in s.crew:
		var c: Dictionary = s.crew[id]
		if c.task_id != null and not id in s.tasks[c.task_id].assigned_crew_ids:
			return invalid("Missing reciprocal task assignment: " + id)
		if c.expedition_id != null:
			var trip: Variant = s.expeditions[c.expedition_id]
			if not trip is Dictionary or not trip.get("crew_ids") is Array \
					or not id in trip.crew_ids or trip.get("task_id") != c.task_id or trip.get("status") == "completed":
				return invalid("Missing reciprocal expedition assignment: " + id)

	for id in s.expeditions:
		var e: Variant = s.expeditions[id]
		if not fields(e, EVA_FIELDS) or not name_is_valid(id) or e.id != id \
				or not sites.has(e.site_id) or not s.tasks.has(e.task_id) \
				or not ids(e.crew_ids, s.crew) or e.crew_ids.is_empty() \
				or e.status not in ["outbound", "working", "returning", "stranded", "completed", "failed"] \
				or not name_is_valid(e.route_id) or not e.route_waypoints_m is Array or e.route_waypoints_m.is_empty() \
				or not number(e.route_distance_m, 0.0) or not number(e.route_progress_m, 0.0, e.route_distance_m) \
				or not number(e.work_required_s, 0.0) or not number(e.work_completed_s, 0.0, e.work_required_s) \
				or not e.suit_stores is Dictionary or e.suit_stores.size() != e.crew_ids.size() \
				or not amounts(e.cargo, resources) or (e.return_margin_s != null and not number(e.return_margin_s)) \
				or not e.recall_requested is bool:
			return invalid("Invalid expedition record: " + str(id))
		var length := 0.0
		var previous: Variant = null
		for waypoint in e.route_waypoints_m:
			if not point(waypoint):
				return invalid("Invalid EVA waypoint: " + id)
			if previous != null:
				length += Vector2(previous[0], previous[2]).distance_to(Vector2(waypoint[0], waypoint[2]))
			previous = waypoint
		if not is_equal_approx(length, e.route_distance_m):
			return invalid("EVA distance does not match the route: " + id)
		var task: Dictionary = s.tasks[e.task_id]
		if task.expedition_id != id or task.target_id != e.site_id or task.assigned_crew_ids != e.crew_ids \
				or not is_equal_approx(task.required_work_s, e.work_required_s) \
				or not is_equal_approx(task.completed_work_s, e.work_completed_s):
			return invalid("Inconsistent EVA task: " + id)
		if e.status not in TERMINAL_EVA and sites[e.site_id].reserved_by_expedition_id != id:
			return invalid("Missing site reservation: " + id)
		for cid in e.crew_ids:
			var c: Dictionary = s.crew[cid]
			var suit: Variant = e.suit_stores.get(cid)
			var capacity: Dictionary = definitions[c.definition_id].suit_capacity
			if not fields(suit, ["oxygen_kg", "battery_kwh"]) \
					or not number(suit.oxygen_kg, 0.0, capacity.oxygen_kg) \
					or not number(suit.battery_kwh, 0.0, capacity.battery_kwh):
				return invalid("Invalid EVA suit stores: " + id)
			if e.status not in TERMINAL_EVA and (c.expedition_id != id or c.task_id != e.task_id):
				return invalid("Inconsistent EVA crew link: " + id)
			if e.status == "completed" and (suit.oxygen_kg != 0.0 or suit.battery_kwh != 0.0):
				return invalid("Returned suit still holds supplies: " + id)
		if e.status == "completed" and not e.cargo.is_empty():
			return invalid("Returned cargo must already be credited or cached: " + id)

	for id in sites:
		var owner: Variant = sites[id].reserved_by_expedition_id
		if owner != null and (not s.expeditions.has(owner) or s.expeditions[owner].site_id != id \
				or s.expeditions[owner].status in TERMINAL_EVA):
			return invalid("Invalid site reservation: " + str(id))
	for id in s.return_caches:
		if not s.expeditions.has(id) or s.expeditions[id].status != "completed" \
				or not amounts(s.return_caches[id], resources):
			return invalid("Invalid expedition return cache: " + str(id))
	for id in s.completion_markers:
		if not name_is_valid(id) or not name_is_valid(s.completion_markers[id]):
			return invalid("Completion markers must map record IDs to committed effect IDs.")
	for id in s.private_counters:
		if not name_is_valid(id) or not whole(s.private_counters[id], 0):
			return invalid("Private counters must contain nonnegative exact integers.")
	return {"ok": true, "code": "ok", "reason": ""}
