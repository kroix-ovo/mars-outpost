extends RefCounted

const Routes = preload("res://scripts/crew/crew_routes.gd")
const Jobs = preload("res://scripts/tasks/crew_jobs.gd")
const TERMINAL := ["completed", "failed"]
const STORES := {"oxygen_kg": "oxygen_kg", "battery_kwh": "energy_kwh"}
const EPS := 1e-9
const Rates = preload("res://scripts/crew/eva_rates.gd")

var world: RefCounted
var airlock: Array
var definitions: Dictionary
var rates: Dictionary
var policy: Dictionary

func speed(snapshot: Dictionary, ids: Array) -> float:
	var value := INF
	for id in ids:
		var member: Dictionary = snapshot.crew[id]
		if member.status in ["dead", "incapacitated"] or member.health <= 0.0:
			return 0.0
		value = minf(value, definitions[member.definition_id].movement_speed_m_per_s)
	return value * modifier(snapshot, "eva_movement")

func modifier(snapshot: Dictionary, target: String) -> float:
	return Rates.modifier(snapshot, target)

func rate(snapshot: Dictionary, phase: String, store: String) -> float:
	return Rates.rate(snapshot, phase, store, rates, policy)

func error(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason}

func forecast(payload: Dictionary, snapshot: Dictionary) -> Dictionary:
	var site: Dictionary = snapshot.sites.get(payload.site_id, {})
	if site.is_empty():
		return error("unknown_entity", "Salvage site not found.")
	if site.reserved_by_expedition_id != null:
		return error("invalid_state", "Another expedition has reserved this site.")
	var ids: Array = payload.crew_ids.duplicate()
	ids.sort()
	for id in ids:
		if not snapshot.crew.has(id):
			return error("unknown_entity", "Unknown astronaut: " + id)
		if not Jobs.idle(snapshot.crew[id]):
			return error("crew_unavailable", "Release " + snapshot.crew[id].display_name + " before launch.")
	var out := Routes.query(world, snapshot, airlock, site.cell)
	var back := Routes.query(world, snapshot, site.cell, airlock)
	var pace := speed(snapshot, ids)
	if not out.get("reachable", false) or not back.get("reachable", false) or pace <= 0.0:
		return error("route_unreachable", "A usable outbound and return route is required.")
	var seconds := {"outbound": maxf(1.0, ceilf(out.distance_m / pace - EPS)),
		"working": maxf(1.0, ceilf(float(payload.work_duration_s) - EPS)),
		"returning": maxf(1.0, ceilf(back.distance_m / pace - EPS))}
	var stores := {"oxygen_kg": float(payload.oxygen_kg_per_crew),
		"battery_kwh": float(payload.battery_kwh_per_crew)}
	var detail := {"ok": true, "code": "ok", "reason": "", "seconds": seconds,
		"phase_use": {}, "remaining": {}, "minimum": {}, "loaded": stores, "route": out,
		"reserve_fraction": policy.reserve_fraction}
	for store in STORES:
		var total := 0.0
		for phase in seconds:
			var amount := float(seconds[phase]) * rate(snapshot, phase, store)
			if not detail.phase_use.has(phase):
				detail.phase_use[phase] = {}
			detail.phase_use[phase][store] = amount
			total += amount
		detail.remaining[store] = stores[store] - total
		detail.minimum[store] = total / (1.0 - float(policy.reserve_fraction))
	for store in STORES:
		if float(stores[store]) + EPS < float(detail.minimum[store]):
			detail.merge(error("reserve_insufficient",
				"Load at least %.5f %s per astronaut for travel, work and emergency reserve." %
				[detail.minimum[store], store]), true)
			return detail
	for id in ids:
		var capacity: Dictionary = definitions[snapshot.crew[id].definition_id].suit_capacity
		for store in STORES:
			if float(stores[store]) > float(capacity[store]) + EPS:
				detail.merge(error("capacity_exceeded",
					"Requested %s exceeds %s’s suit capacity." % [store, snapshot.crew[id].display_name]), true)
				return detail
	for store in STORES:
		var stock: Dictionary = snapshot.resources.get(STORES[store], {})
		if stock.is_empty() or float(stores[store]) * ids.size() > float(stock.amount) - float(stock.reserved) + EPS:
			detail.merge(error("insufficient_resources", "Base stock cannot fill all suits: " + STORES[store]), true)
			return detail
	return detail

func start(payload: Dictionary, snapshot: Dictionary, proposal: Dictionary) -> Dictionary:
	var estimate := forecast(payload, snapshot)
	if not estimate.ok:
		proposal.merge(error(estimate.code, estimate.reason), true)
		return proposal
	var ids: Array = payload.crew_ids.duplicate()
	ids.sort()
	var route: Dictionary = estimate.route
	var initial_margin := INF
	for key in STORES:
		var use := rate(snapshot, "returning", key)
		if use > 0.0:
			initial_margin = minf(initial_margin, float(estimate.loaded[key]) / use)
	var request := transfer("new_expedition", "eva_load", str(int(snapshot.clock.tick_index)))
	var suit := {}
	for id in ids:
		suit[id] = {"oxygen_kg": 0.0, "battery_kwh": 0.0}
		for store in STORES:
			var amount: float = estimate.loaded[store]
			if amount > 0.0:
				request.credits[suit_path("new_expedition", id, store)] = amount
				request.debits["base/" + STORES[store]] = amount * ids.size()
		var member: Dictionary = snapshot.crew[id].duplicate(true)
		member.merge({"task_id": "new_task", "expedition_id": "new_expedition", "status": "eva",
			"location_kind": "eva", "position_m": route.waypoints_m[0].duplicate()}, true)
		proposal.crew_updates[id] = member
	var duration: float = payload.work_duration_s
	proposal.task_updates["new_task"] = {"id": "new_task", "kind": "eva", "target_id": payload.site_id,
		"status": "active", "priority": 50, "crew_required": ids.size(), "assigned_crew_ids": ids.duplicate(),
		"required_work_s": duration, "completed_work_s": 0.0, "blocked_code": null,
		"expedition_id": "new_expedition"}
	var expedition := {"id": "new_expedition", "site_id": payload.site_id, "task_id": "new_task",
		"crew_ids": ids, "status": "outbound", "route_id": route.route_id,
		"route_waypoints_m": route.waypoints_m.duplicate(true), "route_distance_m": route.distance_m,
		"route_progress_m": 0.0, "work_required_s": duration, "work_completed_s": 0.0,
		"suit_stores": suit, "cargo": {},
		"return_margin_s": initial_margin if is_finite(initial_margin) else null, "recall_requested": false}
	proposal.expedition_updates["new_expedition"] = expedition
	append_transfer(proposal, request)
	proposal.result_data = {"expedition_id": "new_expedition", "task_id": "new_task"}
	event(proposal, expedition, "eva_launched")
	return proposal

func recall(id: String, snapshot: Dictionary, proposal: Dictionary) -> Dictionary:
	proposal.result_data = {"expedition_id": id}
	if not snapshot.expeditions.has(id):
		proposal.merge(error("unknown_entity", "Expedition not found."), true)
		return proposal
	var trip: Dictionary = snapshot.expeditions[id].duplicate(true)
	if trip.status in TERMINAL:
		proposal.merge(error("invalid_state", "This expedition has already ended."), true)
		return proposal
	if trip.status == "returning":
		return proposal
	var route := return_route(trip, snapshot)
	if not route.get("reachable", false):
		if trip.status == "stranded":
			proposal.merge(error("route_unreachable", "Return route is still blocked."), true)
			return proposal
		strand(trip, snapshot, proposal)
	else:
		set_return(trip, route)
		trip.return_margin_s = margin(trip, snapshot, route.distance_m)
		task_status(trip, snapshot, proposal, "active", null)
	trip.recall_requested = true
	proposal.expedition_updates[id] = trip
	event(proposal, trip, "eva_recalled")
	return proposal

func return_route(trip: Dictionary, snapshot: Dictionary) -> Dictionary:
	return Routes.from_progress(world, snapshot, trip.route_waypoints_m, trip.route_progress_m, airlock)

func set_return(trip: Dictionary, route: Dictionary) -> void:
	trip.merge({"status": "returning", "route_id": route.route_id,
		"route_waypoints_m": route.waypoints_m.duplicate(true), "route_distance_m": route.distance_m,
		"route_progress_m": 0.0}, true)

func strand(trip: Dictionary, snapshot: Dictionary, proposal: Dictionary) -> void:
	trip.status = "stranded"
	trip.return_margin_s = null
	task_status(trip, snapshot, proposal, "blocked", "route_unreachable")

func task_status(trip: Dictionary, snapshot: Dictionary, proposal: Dictionary,
		status: String, blocked: Variant) -> void:
	var job: Dictionary = snapshot.tasks[trip.task_id].duplicate(true)
	job.status = status
	job.blocked_code = blocked
	proposal.task_updates[job.id] = job

func margin(trip: Dictionary, snapshot: Dictionary, return_m: float) -> Variant:
	var pace := speed(snapshot, trip.crew_ids)
	if pace <= 0.0:
		return null
	var endurance := INF
	for id in trip.crew_ids:
		for store in STORES:
			var use := rate(snapshot, "returning", store)
			if use > 0.0:
				endurance = minf(endurance, float(trip.suit_stores[id][store]) / use)
	return endurance - ceilf(return_m / pace - EPS) if is_finite(endurance) else null

func plan(snapshot: Dictionary, proposal: Dictionary, dt: float, context: Dictionary) -> void:
	var free: Dictionary = {}
	for resource in snapshot.resources:
		var account: Dictionary = snapshot.resources[resource]
		free[resource] = INF if account.capacity == null else maxf(0.0, account.capacity - account.amount)
	for id in Jobs.sorted_ids(snapshot.expeditions):
		var trip: Dictionary = snapshot.expeditions[id].duplicate(true)
		if trip.status in TERMINAL:
			continue
		var unmet := false
		var exhausted := false
		for cid in trip.crew_ids:
			var needs: Array = context.unmet_needs.get(cid, [])
			unmet = unmet or not needs.is_empty()
			exhausted = exhausted or "oxygen" in needs or "suit_energy" in needs
		var pace := speed(snapshot, trip.crew_ids)
		if pace <= EPS or (exhausted and policy.get("fail_on_suit_exhaustion", false)):
			fail(trip, snapshot, proposal, "crew_unavailable" if pace <= EPS else "reserve_insufficient")
		elif trip.status in ["outbound", "returning"]:
			var destination: Array = airlock if trip.status == "returning" else snapshot.sites[trip.site_id].cell
			var legal := Routes.from_progress(world, snapshot, trip.route_waypoints_m,
				trip.route_progress_m, destination)
			if not legal.get("reachable", false) or not Routes.saved_route_clear(world, snapshot, trip.route_waypoints_m, trip.route_progress_m):
				strand(trip, snapshot, proposal)
			else:
				trip.route_progress_m = minf(trip.route_distance_m, trip.route_progress_m + pace * dt)
				var arrived: bool = trip.route_progress_m >= trip.route_distance_m - EPS
				var point := Routes.position(trip.route_waypoints_m, trip.route_progress_m)
				for cid in trip.crew_ids:
					var member: Dictionary = snapshot.crew[cid].duplicate(true)
					member.position_m = point.duplicate()
					proposal.crew_updates[cid] = member
				if arrived and trip.status == "outbound":
					trip.status = "working"
				elif arrived:
					finish(trip, snapshot, proposal, context.tick_index, free)
		elif trip.status == "working":
			var back := return_route(trip, snapshot)
			if not back.get("reachable", false):
				strand(trip, snapshot, proposal)
			elif unmet:
				task_status(trip, snapshot, proposal, "blocked", "unmet_needs")
			else:
				task_status(trip, snapshot, proposal, "active", null)
				trip.work_completed_s = minf(trip.work_required_s, trip.work_completed_s + dt)
				if trip.work_completed_s >= trip.work_required_s - EPS:
					collect(trip, snapshot, proposal, context.tick_index)
					set_return(trip, back)
		if trip.status == "returning":
			trip.return_margin_s = margin(trip, snapshot, trip.route_distance_m - trip.route_progress_m)
		elif trip.status in ["outbound", "working"]:
			var back := return_route(trip, snapshot)
			trip.return_margin_s = margin(trip, snapshot, back.distance_m) if back.get("reachable", false) else null
		if trip != snapshot.expeditions[id]:
			proposal.expedition_updates[id] = trip

func fail(trip: Dictionary, snapshot: Dictionary, proposal: Dictionary, code: String) -> void:
	trip.status = "failed"
	trip.return_margin_s = null
	task_status(trip, snapshot, proposal, "failed", code)

func collect(trip: Dictionary, snapshot: Dictionary, proposal: Dictionary, tick: int) -> void:
	var capacity := 0
	for id in trip.crew_ids:
		capacity += int(definitions[snapshot.crew[id].definition_id].carry_capacity_count)
	var cargo: Dictionary = snapshot.sites[trip.site_id].remaining_cargo
	var request := transfer(trip.id, "salvage_collect", str(tick))
	for resource in Jobs.sorted_ids(cargo):
		if snapshot.resources.get(resource, {}).get("unit") != "count":
			continue # v2 crew definitions declare item-count capacity only.
		var amount := mini(capacity, floori(cargo[resource]))
		if amount > 0:
			request.debits["site/%s/%s" % [trip.site_id, resource]] = amount
			request.credits["cargo/%s/%s" % [trip.id, resource]] = amount
			capacity -= amount
	append_transfer(proposal, request)

func finish(trip: Dictionary, snapshot: Dictionary, proposal: Dictionary, tick: int, free: Dictionary) -> void:
	var suits := transfer(trip.id, "eva_return", str(tick))
	for id in trip.crew_ids:
		var member: Dictionary = Jobs.release(proposal.crew_updates.get(id, snapshot.crew[id]))
		member.location_kind = "base"
		proposal.crew_updates[id] = member
		for store in STORES:
			var amount: float = trip.suit_stores[id][store]
			if amount > 0.0:
				suits.debits[suit_path(trip.id, id, store)] = amount
				credit(suits, STORES[store], amount, "loss/" + STORES[store], free)
	append_transfer(proposal, suits)
	var cargo := transfer(trip.id, "cargo_return", str(tick))
	for resource in Jobs.sorted_ids(trip.cargo):
		var amount: float = trip.cargo[resource]
		if amount > 0.0:
			cargo.debits["cargo/%s/%s" % [trip.id, resource]] = amount
			credit(cargo, resource, amount, "return_cache/%s/%s" % [trip.id, resource], free)
	append_transfer(proposal, cargo)
	trip.status = "completed"
	trip.return_margin_s = null
	task_status(trip, snapshot, proposal,
		"completed" if trip.work_completed_s >= trip.work_required_s - EPS else "cancelled", null)
	event(proposal, trip, "eva_returned")

func credit(request: Dictionary, resource: String, amount: float, overflow_path: String,
		free: Dictionary) -> void:
	var accepted := minf(amount, float(free.get(resource, 0.0)))
	if accepted > 0.0:
		var path := "base/" + resource
		request.credits[path] = float(request.credits.get(path, 0.0)) + accepted
		free[resource] -= accepted
	if amount > accepted:
		request.credits[overflow_path] = float(request.credits.get(overflow_path, 0.0)) + amount - accepted

func suit_path(expedition: String, crew: String, store: String) -> String:
	return "suit/%s/%s/%s" % [expedition, crew, store]

func transfer(owner: String, kind: String, when: String) -> Dictionary:
	return {"effect_id": "crew_tasks:%s:%s:%s" % [owner, kind, when],
		"kind": kind, "debits": {}, "credits": {}, "owner_id": owner}

func append_transfer(proposal: Dictionary, request: Dictionary) -> void:
	if not request.debits.is_empty():
		proposal.resource_requests.append(request)

func event(proposal: Dictionary, trip: Dictionary, type: String) -> void:
	var ids: Array = trip.crew_ids + [trip.id, trip.task_id, trip.site_id]
	ids.sort()
	proposal.events.append({"type": type, "entity_ids": ids,
		"data": {"expedition_id": trip.id, "task_id": trip.task_id, "site_id": trip.site_id}})
