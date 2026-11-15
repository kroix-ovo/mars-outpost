extends RefCounted

const Routes = preload("res://scripts/crew/crew_routes.gd")
const TERMINAL := ["cancelled", "completed", "failed"]

static func sorted_ids(records: Dictionary) -> Array:
	var ids := records.keys()
	ids.sort()
	return ids

static func idle(member: Dictionary) -> bool:
	return member.status == "idle" and member.location_kind == "base" and member.task_id == null \
		and member.expedition_id == null and member.health > 0.0

static func release(member: Dictionary) -> Dictionary:
	var updated := member.duplicate(true)
	updated.task_id = null
	updated.expedition_id = null
	if updated.status not in ["dead", "incapacitated"]:
		updated.status = "idle"
	return updated

static func template(templates: Dictionary, kind: String, work_s: float) -> Dictionary:
	if kind not in ["construct", "repair", "farm"] or work_s <= 0.0 or not is_finite(work_s):
		return {}
	var config: Dictionary = templates.get(kind, {})
	return {"kind": kind, "crew_required": int(config.get("crew_required", 1)),
		"priority": int(config.get("default_priority", 50)), "required_work_s": work_s}

static func productivity(member: Dictionary, kind: String, templates: Dictionary) -> float:
	var job: Dictionary = templates.get(kind, {})
	var skill := "botany" if kind == "farm" else "engineering"
	var factor := 1.0 + float(job.get("skill_weight", 0.0)) * float(member.skills.get(skill, 0.0))
	return float(job.get("labor_rate_work_s_per_crew_s", 1.0)) * factor \
		* clampf(1.0 - member.fatigue, 0.0, 1.0) * float(member.health)

static func assignment_problem(snapshot: Dictionary, task: Dictionary) -> String:
	var building: Dictionary = snapshot.buildings.get(task.target_id, {})
	if building.is_empty() or building.lifecycle == "destroyed":
		return "unknown_entity"
	match task.kind:
		"construct":
			if building.lifecycle != "constructing":
				return "invalid_state"
		"repair":
			if building.lifecycle != "commissioned" or building.condition >= 1.0:
				return "invalid_state"
		"farm":
			if building.lifecycle != "commissioned" or not building.enabled:
				return "invalid_state"
	return ""

static func plan(snapshot: Dictionary, proposal: Dictionary, dt: float, context: Dictionary,
		world: RefCounted, buildings: Dictionary, crew_defs: Dictionary, templates: Dictionary) -> void:
	var ids := sorted_ids(snapshot.tasks)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var pa: int = snapshot.tasks[a].priority
		var pb: int = snapshot.tasks[b].priority
		return a < b if pa == pb else pa > pb)
	var intent: bool = context.phase == "intent"
	for id in ids:
		var job: Dictionary = snapshot.tasks[id].duplicate(true)
		if job.kind == "eva":
			continue
		var terminal: bool = job.status in TERMINAL
		if intent:
			for cid in job.assigned_crew_ids.duplicate():
				var member: Dictionary = snapshot.crew[cid]
				if member.task_id == id and (terminal or member.status in ["dead", "incapacitated"]):
					proposal.crew_updates[cid] = release(member)
					if not terminal:
						job.assigned_crew_ids.erase(cid)
		if terminal:
			continue
		var problem := assignment_problem(snapshot, job)
		var present := 0
		var arrived: Array = []
		var assigned: Array = job.assigned_crew_ids.duplicate()
		assigned.sort()
		for cid in assigned:
			var member: Dictionary = snapshot.crew[cid]
			if member.task_id != id or member.status in ["dead", "incapacitated"]:
				continue
			var updated := member.duplicate(true)
			var route: Dictionary = {}
			if problem.is_empty():
				var target: Dictionary = snapshot.buildings[job.target_id]
				route = Routes.to_building(world, snapshot, member.position_m, target,
					buildings.get(target.definition_id, {}))
			if not route.get("reachable", false):
				updated.status = "idle" # still reserved by task_id
				if problem.is_empty():
					problem = "route_unreachable"
			elif route.distance_m > 1e-8:
				updated.status = "travelling"
				if not intent:
					var speed: float = crew_defs[member.definition_id].movement_speed_m_per_s
					updated.position_m = Routes.position(route.waypoints_m, speed * dt)
			else:
				present += 1
				var unmet: Array = context.get("unmet_needs", {}).get(cid, [])
				var building: Dictionary = snapshot.buildings[job.target_id]
				var powered: bool = job.kind != "farm" or building.power_requested_kw <= 0.0 \
					or building.power_served_kw > 0.0
				if not intent and not powered:
					updated.status = "idle"
					problem = "no_power"
				elif not unmet.is_empty():
					updated.status = "idle"
					problem = "unmet_needs"
				elif productivity(member, job.kind, templates) <= 0.0:
					updated.status = "idle"
					problem = "crew_unavailable"
				else:
					arrived.append(cid)
					updated.status = "working"
			proposal.crew_updates[cid] = updated
		if not problem.is_empty():
			job.status = "blocked"
			job.blocked_code = problem
		elif present < int(job.crew_required):
			job.status = "queued"
			job.blocked_code = null
		else:
			job.status = "active"
			job.blocked_code = null
			if not intent:
				for cid in arrived:
					var member: Dictionary = snapshot.crew[cid]
					proposal.labor.append({"task_id": id, "crew_id": cid,
						"work_s": productivity(member, job.kind, templates) * dt})
		if job != snapshot.tasks[id]:
			proposal.task_updates[id] = job

	var active_rates: Dictionary = templates.get("fatigue", {})
	if not intent:
		for cid in sorted_ids(snapshot.crew):
			var member: Dictionary = proposal.crew_updates.get(cid, snapshot.crew[cid]).duplicate(true)
			var rate := float(active_rates.get(member.status, 0.0))
			if rate != 0.0:
				member.fatigue = clampf(member.fatigue + dt * rate, 0.0, 1.0)
				proposal.crew_updates[cid] = member
