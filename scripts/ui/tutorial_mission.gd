extends RefCounted
## Interactive tutorial mission: a read-only guide that decides the ONE current step from the
## committed simulation snapshot and the live UI state (selection, open tab, placement mode).
##
## It never sends commands, writes balances or completes tasks. The HUD supplies a context
## dictionary (see `evaluate`) and draws the returned step; the player performs every action.
## The only state kept here is which explanations the player acknowledged, plus a baseline of
## records that existed when the colony started, so "new" trips/modules can be recognised.
##
## Steps are evaluated in order every time; the first step that is not done is current. Each
## step's `done` test also accepts any later outcome, so the tutorial never deadlocks when the
## player acts out of order, and falls back to an earlier step if a precondition is lost
## (selection cleared, construction cancelled, trip returned empty...).

const TERMINAL := ["completed", "cancelled", "failed"]

var active := true
var finished := false
var acks: Dictionary = {}
var _campaign := ""
var _baseline: Dictionary = {}
var _systems_seen := false
var _last_index := -1
var _last_phase := ""
var _last_title := ""
var flash := ""  # "✓ ..." acknowledgement for the step just completed
var flash_until_ms := 0


func restart() -> void:
	active = true
	finished = false
	acks.clear()
	_campaign = ""
	_baseline = {}
	_systems_seen = false
	_last_index = -1
	_last_phase = ""
	flash = ""


func skip() -> void:
	active = false


func acknowledge(step_id: String) -> void:
	acks[step_id] = true
	if step_id == "debrief":
		finished = true
		active = false


func mark_systems_seen() -> void:
	_systems_seen = true


func needs_baseline(snapshot: Dictionary) -> bool:
	return str(snapshot.get("campaign_id", "")) != _campaign


func set_baseline(snapshot: Dictionary) -> void:
	## Called once per colony start (and on any restart of that colony).
	_campaign = str(snapshot.get("campaign_id", ""))
	_baseline = {
		"buildings": snapshot.get("buildings", {}).keys(),
		"expeditions": snapshot.get("expeditions", {}).keys(),
		"tasks": snapshot.get("tasks", {}).duplicate(true),
		"oxygen_capacity": snapshot.get("resources", {}).get("oxygen_kg", {}).get("capacity", 0.0),
	}
	_systems_seen = false
	# Explanations are per colony: a restarted training colony replays them only if unseen.
	for key in acks.keys():
		if str(key).begins_with("ref_") or key in ["home", "built", "debrief"]:
			acks.erase(key)


## ctx keys: snapshot, training (bool), tab (String), drawer_open (bool), selected_crew (Array),
## selected_site, selected_task, catalog_selected, storage_id (definition), storage_cost (Dict),
## placement {active, definition_id, valid, reason}, forecast_ok, forecast_reason,
## recommended_cell (Array), last_failure (String), sim_failed (String), names (crew id -> name),
## catalog_names (definition id -> display name).
func evaluate(ctx: Dictionary) -> Dictionary:
	if not active:
		return {}
	var steps: Array = _training_steps(ctx) if ctx.training else _reference_steps(ctx)
	var phase := "training" if ctx.training else "reference"
	var index := steps.size() - 1
	for i in steps.size():
		if not steps[i].done:
			index = i
			break
	var step: Dictionary = steps[index]
	# Acknowledge forward progress within a phase, never backwards moves.
	if phase == _last_phase and index > _last_index and _last_index >= 0:
		flash = "✓  " + _last_title
		flash_until_ms = Time.get_ticks_msec() + 3500
	_last_phase = phase
	_last_index = index
	_last_title = str(step.title)
	step.index = index
	step.total = steps.size()
	step.phase = phase
	step.phase_title = "First shift (training)" if ctx.training else "Colony repairs"
	step.checklist = []
	for i in steps.size():
		step.checklist.append({"title": steps[i].title, "done": i < index, "current": i == index})
	if not str(ctx.get("sim_failed", "")).is_empty():
		step.recovery = "The simulation stopped: %s. Restart this colony to continue the tutorial." % ctx.sim_failed
		step.buttons = [{"id": "restart_training" if ctx.training else "restart_reference", "label": "Restart this colony"}]
	return step


# ---------------------------------------------------------------- training

func _training_steps(ctx: Dictionary) -> Array:
	var s: Dictionary = ctx.snapshot
	var w := _training_facts(ctx)
	var steps: Array = []
	var ack := func(id: String) -> bool: return acks.has(id)
	steps.append(_step("welcome", "Welcome, commander",
		"You command six astronauts at a small outpost on Mars. In this training shift you will send two of them on a spacewalk to recover supplies, use those supplies to build a storage module, and then learn repairs in a second colony.",
		"Press Start tutorial when you are ready. The clock stays paused until you start it.",
		"This training colony uses simple practice numbers, not real mission data.",
		{}, ack.call("welcome"), true,
		[{"id": "welcome", "label": "Start tutorial"}, {"id": "skip", "label": "Skip to free play"}]))
	steps.append(_step("orient", "Your habitat and supplies",
		"The tall capsule is your landing habitat; the crew lives inside. The bar along the top shows what keeps them alive: oxygen, water, power and battery charge. Point at any number for details.",
		"Have a look, then press Next.",
		"Running out of oxygen or power is how missions fail, so check this bar often.",
		{"kind": "world", "id": "lander", "label": "Habitat"}, ack.call("orient"), false,
		[{"id": "orient", "label": "Next"}]))
	# --- Salvage loop (repeats until the colony can afford storage) ---
	var eva_done: bool = w.has_materials or w.storage_placed
	var first: String = w.idle[0] if w.idle.size() > 0 else ""
	var second: String = w.idle[1] if w.idle.size() > 1 else ""
	var selected_idle: Array = w.selected_idle
	var recovery := str(w.trip_recovery)
	if not w.busy_selected.is_empty():
		recovery = "%s is busy right now. Click an idle astronaut instead." % ctx.names.get(w.busy_selected[0], "That astronaut")
	var pick_one := _step("select_one", "Pick an astronaut",
		"These are your astronauts. To send people outside you first choose who goes.",
		"Click %s in the crew list." % ctx.names.get(first, "an idle astronaut"),
		"Every job and trip needs people, so most actions start in this list.",
		{"kind": "crew", "id": first}, eva_done or w.trip_active or selected_idle.size() >= 1, false, [])
	pick_one.recovery = recovery
	steps.append(pick_one)
	var add_target: String = second
	if selected_idle.size() == 1 and selected_idle[0] == second:
		add_target = first
	var pick_two := _step("select_two", "Add a second astronaut",
		"Each astronaut can carry 3 items. Storage costs 10 alloy and 2 electronics, so one person cannot bring back enough.",
		"Hold Ctrl (or Shift) and click %s to add them." % ctx.names.get(add_target, "another idle astronaut"),
		"Two people carry twice the salvage.",
		{"kind": "crew", "id": add_target}, eva_done or w.trip_active or selected_idle.size() >= 2, false,
		[{"id": "add_crew:" + add_target, "label": "Add %s for me" % ctx.names.get(add_target, "them")}] if not add_target.is_empty() else [])
	pick_two.recovery = recovery
	steps.append(pick_two)
	steps.append(_step("open_eva", "Plan a spacewalk",
		"A spacewalk, or EVA (extra-vehicular activity), sends suited astronauts outside. Suits carry their own oxygen and battery power.",
		"Click the EVA tab in mission control.",
		"The EVA tab plans trips and shows whether the suits have enough air for the round trip.",
		{"kind": "tab", "id": "EVA"}, eva_done or w.trip_active or ctx.tab == "EVA", false, []))
	var forecast := _step("forecast", "Check the safety forecast",
		"The yellow flag marks a salvage cache. The forecast checks that every suit has enough oxygen and battery to walk there, work, and walk back, with a safety reserve left over.",
		"When the forecast says it is safe, press Next." if ctx.forecast_ok else "Fix the problem shown below, then press Next.",
		"Never launch a trip the forecast calls unsafe; astronauts cannot refill outside.",
		{"kind": "control", "id": "eva_summary", "world": {"kind": "site", "id": w.site_id}},
		eva_done or w.trip_active or acks.has("forecast"), false,
		[{"id": "forecast", "label": "Next", "disabled": not ctx.forecast_ok}])
	if not ctx.forecast_ok:
		forecast.recovery = _forecast_help(str(ctx.forecast_reason))
	steps.append(forecast)
	var launch := _step("launch", "Launch the expedition",
		"Everything is ready. Launching moves the suit supplies from the habitat into the suits.",
		"Click Launch expedition.",
		"Supplies only leave the habitat when you launch.",
		{"kind": "control", "id": "launch"}, eva_done or w.trip_active, false, [])
	if not ctx.forecast_ok:
		launch.recovery = _forecast_help(str(ctx.forecast_reason))
	steps.append(launch)
	steps.append(_step("resume", "Start the clock",
		"The clock is paused, so the crew is waiting at the airlock.",
		"Press 1× to start time. 5× and 20× make it faster; Space pauses again.",
		"Commands work while paused, so pausing is the safe way to plan.",
		{"kind": "speed", "id": "1"}, eva_done or (w.trip_active and int(s.clock.time_scale) > 0), false, []))
	var watch := _step("watch_trip", "Watch the spacewalk",
		_trip_phase_text(w.trip_status),
		"Wait for them to come home. Press 20× if you want it to go faster.",
		"The trip has three parts: walk out, collect salvage, walk back.",
		{"kind": "world", "id": "trip", "label": "Spacewalk", "secondary": "trip_text"}, eva_done, false, [])
	steps.append(watch)
	steps.append(_step("home", "Crew home with salvage",
		"Welcome back! The salvage is unloaded into the colony store. You now have %s alloy and %s electronics: enough for a storage module (10 alloy, 2 electronics)." % [_n(w.alloy), _n(w.electronics)],
		"Press Next to start building.",
		"Building costs materials, which is why salvage came first.",
		{"kind": "world", "id": "lander", "label": "Crew home"}, acks.has("home") or w.storage_placed, false,
		[{"id": "home", "label": "Next"}]))
	# --- Build ---
	var built: bool = w.storage_placed
	steps.append(_step("open_build", "Open the Build tab",
		"New modules are placed from the Build tab.",
		"Click the Build tab.",
		"",
		{"kind": "tab", "id": "Build"}, built or ctx.tab == "Build" or w.placing_storage, false, []))
	var storage_name: String = ctx.catalog_names.get(ctx.storage_id, "Storage Module")
	steps.append(_step("choose_storage", "Choose the storage module",
		"A storage module adds tank space: %s." % ctx.get("storage_effect", "more storage capacity"),
		"Pick “%s” in the Place a module list." % storage_name,
		"",
		{"kind": "control", "id": "catalog"}, built or w.placing_storage or ctx.catalog_selected == ctx.storage_id, false, []))
	var mode := _step("placement_mode", "Pick a spot on the map",
		"You place modules directly on the ground around the habitat.",
		"Click Choose a cell on the map.",
		"",
		{"kind": "control", "id": "place_on_map"}, built or w.placing_storage, false, [])
	if ctx.placement.active and ctx.placement.definition_id != ctx.storage_id:
		mode.recovery = "You are placing a different module. Press Esc to cancel it first."
	steps.append(mode)
	var place := _step("place", "Place it on the glowing square",
		"A green outline means the spot is free and buildable; red means blocked. The habitat needs a clear path to every module's door.",
		"Move the cursor onto the glowing square and left-click. R rotates, Esc cancels.",
		"Placing spends the materials right away; the crew still has to build it.",
		{"kind": "world", "id": "cell", "label": "Place here"}, built, false, [])
	if ctx.placement.active and not ctx.placement.get("valid", true) and not str(ctx.placement.get("reason", "")).is_empty():
		place.recovery = "That spot will not work: %s. Try the glowing square." % _plain(str(ctx.placement.reason))
	steps.append(place)
	# --- Assign ---
	var assigned: bool = w.storage_assigned or w.storage_commissioned
	steps.append(_step("open_jobs", "Find the construction job",
		"The module is only a frame until someone builds it. Every piece of work is a job.",
		"Click the Jobs tab.",
		"",
		{"kind": "tab", "id": "Jobs"}, assigned or ctx.tab == "Jobs", false, []))
	steps.append(_step("select_job", "Choose the construction job",
		"This list shows every job in the colony.",
		"Choose “Construct · %s” in the Job list." % storage_name,
		"",
		{"kind": "control", "id": "tasks"}, assigned or (not w.storage_task.is_empty() and ctx.selected_task == w.storage_task), false, []))
	steps.append(_step("suggest", "Let mission control pick a builder",
		"Suggest crew selects free astronauts with the best skills for this job.",
		"Click Suggest crew.",
		"You can also pick people yourself in the crew list.",
		{"kind": "control", "id": "suggest"}, assigned or not selected_idle.is_empty(), false, []))
	steps.append(_step("assign", "Assign the builder",
		"The highlighted astronaut in the crew list will do the work.",
		"Click Assign selected.",
		"",
		{"kind": "control", "id": "assign"}, assigned, false, []))
	var progress: float = w.storage_progress
	steps.append(_step("run_build", "Let them build",
		"The builder walks to the module's door, then construction progress fills up.",
		"Press 5× to speed up time." if int(s.clock.time_scale) == 0 else "Construction %d%%. Keep watching; 20× is fastest." % roundi(progress * 100.0),
		"Modules only work once construction reaches 100%.",
		{"kind": "speed", "id": "5"} if int(s.clock.time_scale) == 0 else {"kind": "world", "id": "storage", "label": "Construction"},
		w.storage_commissioned, false, []))
	steps.append(_step("built", "Storage online!",
		"The new module is commissioned. Oxygen storage went from %s kg to %s kg, so the colony can hold a bigger reserve." % [_n(w.capacity_before), _n(w.capacity_now)],
		"Press Next.",
		"More storage buys time when equipment fails.",
		{"kind": "world", "id": "storage", "label": "New storage"}, acks.has("built"), false,
		[{"id": "built", "label": "Next"}]))
	steps.append(_step("to_reference", "Training complete",
		"You recovered salvage, built storage and staffed the job: the whole colony loop. Next is a reference colony where crew use of oxygen, water and food follows researched reference rates, and damaged equipment needs repair.",
		"Press Go to reference colony. This starts that colony from the beginning; the training colony is closed.",
		"Spacewalks are switched off there because real suit numbers are still being researched.",
		{}, false, true,
		[{"id": "go_reference", "label": "Go to reference colony"}, {"id": "skip", "label": "Stay here in free play"}]))
	# Explain why the salvage loop restarted on whichever spacewalk step is now current.
	if not str(w.trip_recovery).is_empty():
		for step in steps:
			if not step.done:
				if step.id in ["select_one", "select_two", "open_eva", "forecast", "launch"] and not str(step.recovery).contains(w.trip_recovery):
					step.recovery = w.trip_recovery + ("" if str(step.recovery).is_empty() else "\n" + str(step.recovery))
				break
	if w.deadlocked:
		for step in steps:
			if not step.done:
				step.recovery = "The training colony no longer has enough materials anywhere for storage. Restart training to try again."
				step.buttons = [{"id": "restart_training", "label": "Restart training colony"}]
				break
	return steps


func _training_facts(ctx: Dictionary) -> Dictionary:
	var s: Dictionary = ctx.snapshot
	var f := {}
	var idle: Array = []
	var ids: Array = s.get("crew", {}).keys()
	ids.sort()
	for id in ids:
		var c: Dictionary = s.crew[id]
		if c.status == "idle" and c.get("location_kind", "base") == "base" and c.get("task_id") == null:
			idle.append(id)
	f.idle = idle
	f.selected_idle = []
	f.busy_selected = []
	for id in ctx.selected_crew:
		(f.selected_idle if id in idle else f.busy_selected).append(id)
	var cost: Dictionary = ctx.storage_cost
	var resources: Dictionary = s.get("resources", {})
	f.alloy = float(resources.get("alloy", {}).get("amount", 0.0))
	f.electronics = float(resources.get("electronics", {}).get("amount", 0.0))
	var affordable := not cost.is_empty()
	for rid in cost:
		var r: Dictionary = resources.get(rid, {})
		if r.is_empty() or float(r.amount) - float(r.reserved) < float(cost[rid]):
			affordable = false
	# The newest storage module this colony did not start with.
	f.storage_building = ""
	var building_ids: Array = s.get("buildings", {}).keys()
	building_ids.sort()
	for id in building_ids:
		var b: Dictionary = s.buildings[id]
		if id not in _baseline.get("buildings", []) and b.definition_id == ctx.storage_id and b.lifecycle != "destroyed":
			f.storage_building = id
	var storage: Dictionary = s.get("buildings", {}).get(f.storage_building, {})
	f.storage_placed = not storage.is_empty()
	f.storage_commissioned = storage.get("lifecycle") == "commissioned"
	f.storage_progress = float(storage.get("construction_progress", 0.0))
	f.storage_task = ""
	f.storage_assigned = false
	for id in s.get("tasks", {}):
		var t: Dictionary = s.tasks[id]
		if t.get("target_id") == f.storage_building and t.kind == "construct" and t.status not in ["cancelled", "failed"]:
			f.storage_task = id
			f.storage_assigned = not t.assigned_crew_ids.is_empty() or t.status == "completed"
	f.has_materials = affordable
	f.placing_storage = ctx.placement.active and ctx.placement.definition_id == ctx.storage_id
	# The newest trip launched in this colony.
	var trip: Dictionary = {}
	var trip_ids: Array = s.get("expeditions", {}).keys()
	trip_ids.sort()
	for id in trip_ids:
		if id not in _baseline.get("expeditions", []):
			trip = s.expeditions[id]
	f.trip_status = str(trip.get("status", ""))
	f.trip_active = not trip.is_empty() and f.trip_status not in ["completed", "failed"]
	f.site_id = ""
	for id in s.get("sites", {}):
		f.site_id = id
		break
	f.trip_recovery = ""
	if not trip.is_empty() and not f.trip_active and not affordable and not f.storage_placed:
		if f.trip_status == "failed":
			f.trip_recovery = "The last spacewalk failed and brought nothing back. Plan a new one."
		elif float(trip.get("work_completed_s", 0.0)) <= 0.0:
			f.trip_recovery = "The last spacewalk was recalled before it collected anything. Send another one."
		else:
			f.trip_recovery = "The crew brought salvage home, but you have %s alloy and %s electronics; storage needs 10 and 2. Send two astronauts to collect the rest." % [_n(f.alloy), _n(f.electronics)]
	# Deadlock: not affordable, nothing placed, no trip out, and the cache cannot cover the gap.
	f.deadlocked = false
	if not affordable and not f.storage_placed and not f.trip_active:
		for rid in cost:
			var remaining := 0.0
			for site in s.get("sites", {}).values():
				remaining += float(site.get("remaining_cargo", {}).get(rid, 0))
			if float(resources.get(rid, {}).get("amount", 0.0)) + remaining < float(cost[rid]):
				f.deadlocked = true
	f.capacity_before = float(_baseline.get("oxygen_capacity", 0.0))
	f.capacity_now = float(resources.get("oxygen_kg", {}).get("capacity", 0.0))
	return f


# ---------------------------------------------------------------- reference

func _reference_steps(ctx: Dictionary) -> Array:
	var s: Dictionary = ctx.snapshot
	var steps: Array = []
	var repairs := _starting_repairs()
	var damaged := "One machine starts damaged" if repairs.size() == 1 else ("%d machines start damaged" % repairs.size() if repairs.size() > 1 else "Nothing starts damaged")
	steps.append(_step("ref_welcome", "The reference colony",
		"This colony uses researched reference rates for how much oxygen, water and food the crew uses; equipment output is a game assumption. %s, and the clock is paused." % damaged,
		"Press Next to look at life support.",
		"Spacewalks are switched off here: real suit oxygen and battery budgets are still being researched, so the game will not invent them.",
		{}, acks.has("ref_welcome"), true, [{"id": "ref_welcome", "label": "Next"}]))
	steps.append(_step("ref_systems", "Open life support",
		"The Systems tab lists every machine that makes oxygen, cleans water or generates power.",
		"Click the Systems tab.",
		"",
		{"kind": "tab", "id": "Systems"}, _systems_seen, false, []))
	steps.append(_step("ref_read", "Read the systems page",
		"Each line is a machine and how much of its job it is doing. “Damaged” means it needs repair; damaged solar panels make less power. Alerts appear at the top right.",
		"Press Next when you have read it.",
		"",
		{"kind": "control", "id": "oxygen_info"}, acks.has("ref_read"), false, [{"id": "ref_read", "label": "Next"}]))
	var all_done := true
	for id in repairs:
		var t: Dictionary = s.get("tasks", {}).get(id, {})
		if t.get("status") != "completed": all_done = false
	var number := 0
	for id in repairs:
		number += 1
		var t: Dictionary = s.get("tasks", {}).get(id, {})
		var target: Dictionary = s.get("buildings", {}).get(t.get("target_id", ""), {})
		var name: String = ctx.catalog_names.get(target.get("definition_id", ""), "module")
		var tag := " (%d of %d)" % [number, repairs.size()] if repairs.size() > 1 else ""
		var done: bool = t.get("status") == "completed"
		var assigned: bool = done or not t.get("assigned_crew_ids", []).is_empty()
		var key := "repair_%s_" % id
		if t.get("status") in ["cancelled", "failed"] or t.is_empty():
			# A cancelled starting repair can never be re-created in this colony, so replace its
			# substeps with one honest recovery step instead of an impossible Assign action.
			var lost := _step(key + "lost", "Repair job cancelled" + tag,
				"The repair job for the %s was cancelled, so it cannot be finished in this colony." % name,
				"Press Restart reference colony to get the repair job back.",
				"Restarting resets this colony to its starting state.",
				{}, false, false, [{"id": "restart_reference", "label": "Restart reference colony"}])
			lost.recovery = "This repair can no longer be completed here."
			steps.append(lost)
			continue
		steps.append(_step(key + "jobs", "Open the repair job" + tag,
			"The %s is damaged (%d%% condition). Repairs are jobs, like construction." % [name, roundi(float(target.get("condition", 1.0)) * 100.0)],
			"Click the Jobs tab.",
			"",
			{"kind": "tab", "id": "Jobs"}, assigned or ctx.tab == "Jobs", false, []))
		steps.append(_step(key + "select", "Choose the repair" + tag,
			"Pick the job for the damaged %s." % name,
			"Choose “Repair · %s” in the Job list." % name,
			"",
			{"kind": "control", "id": "tasks", "world": {"kind": "building", "id": target.get("id", "")}}, assigned or ctx.selected_task == id, false, []))
		var idle_selected := false
		for crew_id in ctx.selected_crew:
			if s.crew.get(crew_id, {}).get("status") == "idle":
				idle_selected = true
		steps.append(_step(key + "suggest", "Pick a repair crew" + tag,
			"Suggest crew picks a free astronaut with good engineering skills.",
			"Click Suggest crew.",
			"",
			{"kind": "control", "id": "suggest"}, assigned or idle_selected, false, []))
		steps.append(_step(key + "assign", "Assign the repair" + tag,
			"The selected astronaut will walk to the panel and fix it.",
			"Click Assign selected.",
			"",
			{"kind": "control", "id": "assign"}, assigned, false, []))
		var running := int(s.clock.time_scale) > 0
		var repair := _step(key + "run", "Let the repair finish" + tag,
			"Repair %.0f of %.0f work-seconds done." % [float(t.get("completed_work_s", 0.0)), float(t.get("required_work_s", 0.0))],
			"Press 5× to run time." if not running else "Watch the condition rise to 100%.",
			"Completed repairs restore the module's output.",
			{"kind": "speed", "id": "5"} if not running else {"kind": "world", "id": "building", "building": target.get("id", ""), "label": "Repair"},
			done, false, [])
		steps.append(repair)
	steps.append(_step("debrief", "Mission debrief",
		_debrief(ctx, repairs.size(), all_done),
		"Press Finish to play freely. You can restart this tutorial from the Guide tab.",
		"",
		{}, acks.has("debrief"), true, [{"id": "debrief", "label": "Finish tutorial"}]))
	return steps


func _starting_repairs() -> Array:
	var repairs: Array = []
	var task_ids: Array = _baseline.get("tasks", {}).keys()
	task_ids.sort()
	for id in task_ids:
		var original: Dictionary = _baseline.tasks[id]
		if original.kind == "repair" and original.status not in TERMINAL:
			repairs.append(id)
	return repairs


func _debrief(ctx: Dictionary, repairs: int, all_done: bool) -> String:
	var lines: Array[String] = []
	lines.append("You learned the whole colony loop: watch supplies, plan a safe spacewalk, turn salvage into a new module, staff jobs, and repair damaged equipment.")
	if all_done and repairs > 0:
		lines.append("All %d starting repair%s finished." % [repairs, "" if repairs == 1 else "s"])
	lines.append("Next: keep oxygen, water and battery charge healthy, react to alerts, and use 20× only when nothing needs attention.")
	return "\n".join(lines)


# ---------------------------------------------------------------- helpers

static func _step(id: String, title: String, body: String, action: String, why: String,
		target: Dictionary, done: bool, centered: bool, buttons: Array) -> Dictionary:
	return {"id": id, "title": title, "body": body, "action": action, "why": why,
		"target": target, "done": done, "centered": centered, "buttons": buttons, "recovery": ""}


static func _trip_phase_text(status: String) -> String:
	match status:
		"outbound": return "The crew is walking out to the salvage cache."
		"working": return "The crew is at the cache, collecting salvage."
		"returning": return "The crew is walking home with the salvage."
		"stranded": return "The way home is blocked. Recall the expedition from the EVA tab once a path is clear."
	return "The crew is preparing at the airlock."


static func _forecast_help(reason: String) -> String:
	if reason.is_empty():
		return ""
	if reason.contains("Select available crew"):
		return "Select two idle astronauts in the crew list first."
	if reason.contains("reserved"):
		return "Another trip is already using this cache. Wait for it to come home."
	return "The forecast says: " + reason


static func _plain(reason: String) -> String:
	return reason.replace("_", " ")


static func _n(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
