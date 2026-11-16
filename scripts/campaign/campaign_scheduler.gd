extends RefCounted
## Persisted scheduled-boundary queue stored in campaign.time. Entries fire in
## (due_tick, phase, sequence) order, one committed transaction per entry.
## Handlers run at whole-tick boundaries only; never from rendered frames.
const Schema = preload("res://scripts/simulation/command_schemas.gd")
const Calendar = preload("res://scripts/campaign/campaign_calendar.gd")
const ENTRY_KEYS = ["id", "due_tick", "phase", "sequence", "kind", "payload"]
const BUILTIN = {"day_start": 0, "shipment_order_deadline": 10, "shipment_arrival": 20}
const MAX_PHASE := 1000
const STOP_REASONS = ["deadline", "shipment", "scheduled"]

static func initial_time(calendar: Dictionary, tick: int, profile: Dictionary) -> Dictionary:
	var time := {"schema_version": 1, "profile_id": profile.id, "base_rate": int(profile.base_rate_sim_s_per_real_s),
		"queue": [], "next_sequence": 1,
		"fast_forward": {"active": false, "target_tick": null, "started_tick": null, "command_id": null,
			"stop_reason": null, "stop_detail": null, "stopped_tick": null}}
	schedule(time, Calendar.next_day_start(calendar, tick), "day_start", {})
	var deadline_cycle := Calendar.next_deadline_cycle(calendar, tick)
	schedule(time, Calendar.order_deadline(calendar, deadline_cycle), "shipment_order_deadline", {"cycle": deadline_cycle})
	var cycle := Calendar.next_shipment_cycle(calendar, tick)
	schedule(time, Calendar.shipment_arrival(calendar, cycle), "shipment_arrival", {"cycle": cycle})
	return time

static func schedule(time: Dictionary, due_tick: int, kind: String, payload: Dictionary, phase: int = -1) -> String:
	## Future packages register their transitions here from inside a transaction.
	var sequence: int = time.next_sequence
	time.next_sequence = sequence + 1
	var entry := {"id": "boundary_%06d" % sequence, "due_tick": due_tick,
		"phase": int(BUILTIN.get(kind, 500)) if phase < 0 else phase, "sequence": sequence,
		"kind": kind, "payload": payload.duplicate(true)}
	var queue: Array = time.queue
	var index := queue.size()
	while index > 0 and before(entry, queue[index - 1]): index -= 1
	queue.insert(index, entry)
	return entry.id

static func cancel(time: Dictionary, id: String) -> bool:
	for index in time.queue.size():
		if time.queue[index].id == id:
			time.queue.remove_at(index)
			return true
	return false

static func before(a: Dictionary, b: Dictionary) -> bool:
	if a.due_tick != b.due_tick: return a.due_tick < b.due_tick
	if a.phase != b.phase: return a.phase < b.phase
	return a.sequence < b.sequence

static func next_due(time: Dictionary) -> int:
	return int(time.queue[0].due_tick) if not time.queue.is_empty() else Schema.MAX_EXACT_INTEGER

static func builtin_handler(kind: String) -> Callable:
	match kind:
		"day_start": return _day_start
		"shipment_order_deadline": return _order_deadline
		"shipment_arrival": return _shipment_arrival
	return Callable()

## Handlers receive the working copy and the popped entry. They may schedule more
## entries, draw from state.rng and return events; the facade commits and numbers them.
static func _day_start(state: RefCounted, entry: Dictionary) -> Dictionary:
	var calendar: Dictionary = state.records.campaign.calendar
	var described := Calendar.describe(calendar, int(entry.due_tick))
	var events: Array = [{"type": "calendar_day", "entity_ids": [],
		"data": {"mission_day": described.mission_day, "month": described.month, "day_of_month": described.day_of_month}}]
	if described.day_of_month == 1:
		events.append({"type": "calendar_month", "entity_ids": [], "data": {"month": described.month}})
	schedule(state.records.campaign.time, int(entry.due_tick) + int(calendar.day_seconds), "day_start", {})
	return {"ok": true, "events": events, "stop": null}

static func _order_deadline(state: RefCounted, entry: Dictionary) -> Dictionary:
	var calendar: Dictionary = state.records.campaign.calendar
	var cycle := int(entry.payload.cycle)
	schedule(state.records.campaign.time, Calendar.order_deadline(calendar, cycle + 1), "shipment_order_deadline", {"cycle": cycle + 1})
	return {"ok": true, "stop": {"reason": "deadline", "detail": "shipment_order:%d" % cycle},
		"events": [{"type": "shipment_order_deadline", "entity_ids": [], "data": {"cycle": cycle, "arrival_s": Calendar.shipment_arrival(calendar, cycle)}}]}

static func _shipment_arrival(state: RefCounted, entry: Dictionary) -> Dictionary:
	# Package 9 owns manifests, unloading and the cargo partition. This is the boundary only.
	var calendar: Dictionary = state.records.campaign.calendar
	var cycle := int(entry.payload.cycle)
	schedule(state.records.campaign.time, Calendar.shipment_arrival(calendar, cycle + 1), "shipment_arrival", {"cycle": cycle + 1})
	return {"ok": true, "stop": {"reason": "shipment", "detail": "cycle:%d" % cycle},
		"events": [{"type": "shipment_due", "entity_ids": [], "data": {"cycle": cycle}}]}

static func validate(time: Variant, calendar: Dictionary, tick: int, profile: Dictionary, kinds: Dictionary) -> Dictionary:
	## `kinds` maps every registered boundary kind to an optional payload validator Callable.
	if not time is Dictionary or not Schema.exact_keys(time, ["schema_version", "profile_id", "base_rate", "queue", "next_sequence", "fast_forward"]):
		return invalid("Invalid campaign time fields.")
	if time.schema_version != 1 or time.profile_id != profile.id or time.base_rate != int(profile.base_rate_sim_s_per_real_s):
		return invalid("Campaign time profile/version differs from this session.")
	if not time.queue is Array or not Schema.whole(time.next_sequence, 1): return invalid("Invalid scheduler queue.")
	var seen := {}
	var builtin_count := {}
	var prior: Dictionary = {}
	for entry in time.queue:
		if not entry is Dictionary or not Schema.exact_keys(entry, ENTRY_KEYS): return invalid("Invalid scheduled boundary.")
		if not Schema.whole(entry.sequence, 1, int(time.next_sequence) - 1) or entry.id != "boundary_%06d" % int(entry.sequence) or seen.has(entry.sequence):
			return invalid("Scheduled boundary identity would be reused.")
		seen[entry.sequence] = true
		# Every boundary at or before the committed tick has already fired.
		if not Schema.whole(entry.due_tick, tick + 1) or not Schema.whole(entry.phase, 0, MAX_PHASE): return invalid("Scheduled boundary is not pending.")
		if not entry.kind is String or not kinds.has(entry.kind) or not entry.payload is Dictionary: return invalid("Unknown scheduled boundary kind.")
		if not prior.is_empty() and not before(prior, entry): return invalid("Scheduled boundaries are out of order.")
		prior = entry
		var due := int(entry.due_tick)
		match entry.kind:
			"day_start":
				if not entry.payload.is_empty() or due != Calendar.next_day_start(calendar, tick): return invalid("Invalid day boundary.")
			"shipment_order_deadline":
				if not Schema.exact_keys(entry.payload, ["cycle"]) or not Schema.whole(entry.payload.cycle, 1) or int(entry.payload.cycle) != Calendar.next_deadline_cycle(calendar, tick) or due != Calendar.order_deadline(calendar, int(entry.payload.cycle)):
					return invalid("Invalid shipment order deadline.")
			"shipment_arrival":
				if not Schema.exact_keys(entry.payload, ["cycle"]) or not Schema.whole(entry.payload.cycle, 1) or int(entry.payload.cycle) != Calendar.next_shipment_cycle(calendar, tick) or due != Calendar.shipment_arrival(calendar, int(entry.payload.cycle)):
					return invalid("Invalid shipment boundary.")
			_:
				var checker: Variant = kinds[entry.kind]
				if checker is Callable and checker.is_valid() and not checker.call(entry.payload): return invalid("Invalid scheduled payload: " + entry.kind)
		if BUILTIN.has(entry.kind):
			if entry.phase != BUILTIN[entry.kind] or builtin_count.has(entry.kind): return invalid("Duplicate or reordered calendar boundary.")
			builtin_count[entry.kind] = true
	if builtin_count.size() != BUILTIN.size(): return invalid("Calendar boundary missing.")
	return validate_fast_forward(time.fast_forward, tick)

static func validate_fast_forward(ff: Variant, tick: int) -> Dictionary:
	if not ff is Dictionary or not Schema.exact_keys(ff, ["active", "target_tick", "started_tick", "command_id", "stop_reason", "stop_detail", "stopped_tick"]) or not ff.active is bool:
		return invalid("Invalid fast-forward record.")
	var never: bool = ff.target_tick == null and ff.started_tick == null and ff.command_id == null and ff.stop_reason == null and ff.stop_detail == null and ff.stopped_tick == null
	if never: return good() if not ff.active else invalid("Active fast-forward has no target.")
	if not Schema.whole(ff.started_tick, 0, tick) or not Schema.whole(ff.target_tick, int(ff.started_tick) + 1) or not Schema.identifier(ff.command_id):
		return invalid("Invalid fast-forward target.")
	if ff.active:
		if ff.stop_reason != null or ff.stop_detail != null or ff.stopped_tick != null or int(ff.target_tick) <= tick: return invalid("Active fast-forward is already finished.")
	elif ff.stop_reason not in ["target_reached", "cancelled", "paused", "danger", "deadline", "shipment", "scheduled", "error"] or not ff.stop_detail is String or not Schema.whole(ff.stopped_tick, int(ff.started_tick), tick) or int(ff.stopped_tick) > int(ff.target_tick):
		return invalid("Invalid fast-forward stop record.")
	return good()

static func good() -> Dictionary:
	return {"ok": true, "code": "ok", "reason": ""}

static func invalid(reason: String) -> Dictionary:
	return {"ok": false, "code": "invalid_save", "reason": reason}
