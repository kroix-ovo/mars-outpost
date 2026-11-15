extends RefCounted
## Presentation-only mission progress, derived from committed snapshots. Reset on colony restart.
## No commands, resource rewards, or simulation/save fields belong to this guide.

var training := true
var done: Dictionary = {}
var _initial_buildings: Dictionary = {}
var _initial_expeditions: Dictionary = {}
var _initial_tasks: Dictionary = {}
var _sites: Dictionary = {}

func reset(snapshot: Dictionary) -> void:
	training = str(snapshot.get("campaign_id", "")).begins_with("fixture_")
	done.clear()
	_initial_buildings = snapshot.get("buildings", {}).duplicate(true)
	_initial_expeditions = snapshot.get("expeditions", {}).duplicate(true)
	_initial_tasks = snapshot.get("tasks", {}).duplicate(true)
	_sites = snapshot.get("sites", {}).duplicate(true)

func observe(snapshot: Dictionary) -> void:
	if training:
		for id in snapshot.get("expeditions", {}):
			var trip: Dictionary = snapshot.expeditions[id]
			if _initial_expeditions.has(id) or trip.status != "completed":
				continue
			# An early recall with no work/cargo must not complete the salvage objective.
			var before: Dictionary = _sites.get(trip.site_id, {}).get("remaining_cargo", {})
			var after: Dictionary = snapshot.sites.get(trip.site_id, {}).get("remaining_cargo", {})
			for resource in before:
				if float(after.get(resource, 0)) < float(before[resource]) and trip.work_completed_s > 0:
					done.salvage = true
		for id in snapshot.get("buildings", {}):
			if _initial_buildings.has(id):
				continue
			var building: Dictionary = snapshot.buildings[id]
			if building.definition_id != "fixture_storage_module":
				continue
			if building.lifecycle == "constructing":
				done.place = true
			if building.lifecycle == "commissioned":
				done.place = true
				done.assign = true
				done.commission = true
		for task in snapshot.get("tasks", {}).values():
			if task.kind == "construct" and not _initial_buildings.has(task.target_id) \
					and snapshot.buildings.get(task.target_id, {}).get("definition_id") == "fixture_storage_module" \
					and task.status not in ["cancelled", "failed"] and not task.assigned_crew_ids.is_empty():
				done.assign = true
	else:
		var found := false
		var repaired := true
		for id in _initial_tasks:
			var original: Dictionary = _initial_tasks[id]
			if original.kind != "repair" or original.status == "completed":
				continue
			found = true
			var task: Dictionary = snapshot.get("tasks", {}).get(id, {})
			var building: Dictionary = snapshot.get("buildings", {}).get(original.target_id, {})
			if task.get("status") != "completed" or float(building.get("condition", 0)) < 0.999:
				repaired = false
		if found and repaired:
			done.repair = true

func objectives() -> Array:
	if training:
		return [
			["salvage", "Bring salvage home", "Select two idle astronauts with Ctrl/Shift. Open EVA, check the forecast and launch. Resume time; wait for work and the return trip to finish. Salvage pays for new modules.", "EVA"],
			["place", "Place a storage module", "Open Build and choose Fixture Storage Module. Choose a cell on the map, then click an open cell to the right of the lander. R rotates; Esc cancels. Placement spends materials.", "Build"],
			["assign", "Staff construction", "Open Jobs, choose the storage construction job, then Suggest crew and Assign selected. A placed module needs crew labor before it can operate.", "Jobs"],
			["commission", "Bring the module online", "Resume at 5× or 20× and watch construction finish. Select the new module to inspect it. Commissioned storage increases the colony's capacity.", "Build"]]
	return [
		["systems", "Inspect life support", "Open Systems to check oxygen, water, power and active alerts before assigning crew. This colony uses reference life-support values; EVA is unavailable here.", "Systems"],
		["repair", "Restore the damaged modules", "Open Jobs. For each repair job, Suggest crew and Assign selected. Resume time and wait for every starting repair to finish. Completed repairs restore module condition.", "Jobs"]]

func current() -> Array:
	for objective in objectives():
		if not done.has(objective[0]):
			return objective
	return []

func completed_count() -> int:
	var count := 0
	for objective in objectives():
		if done.has(objective[0]): count += 1
	return count
