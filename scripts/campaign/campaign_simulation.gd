extends "res://scripts/simulation/simulation.gd"
## Opt-in v3 facade. Reuses v2 handlers and ledger; does not change the live prototype.
##
## Time (package 2): one run loop serves advance, advance_budgeted, step and fast-forward.
## Order at every whole-tick boundary: received commands, due scheduled boundaries,
## fast-forward stop checks, then the next interval. The detailed one-second tick is the
## oracle. A stable interval may instead be replayed: the ledger operands recorded from a
## real tick are re-applied per account, and the real tick must reproduce them at the
## interval's end or the interval is discarded.
const Campaign = preload("res://scripts/campaign/campaign_schema.gd")
const Saves = preload("res://scripts/campaign/campaign_save.gd")
const Commands = preload("res://scripts/campaign/campaign_commands.gd")
const Calendar = preload("res://scripts/campaign/campaign_calendar.gd")
const Scheduler = preload("res://scripts/campaign/campaign_scheduler.gd")
const TapeLedger = preload("res://scripts/campaign/campaign_tape_ledger.gd")
const Hook = preload("res://scripts/campaign/campaign_time_hook.gd")
const Hooks = preload("res://scripts/campaign/campaign_time_hooks.gd")
const SETTLE_LIMIT := 64

var _profile: Dictionary = Campaign.LEGACY_PROFILE.duplicate(true)
var _hooks: Array = Hooks.builtin()
var _boundary_handlers: Dictionary = {}
var _boundary_validators: Dictionary = {}
## "auto" replays stable intervals; "detailed" is the one-second oracle. Not gameplay
## state: both modes must produce identical checkpoints.
var _integration_mode: String = "auto"
# Reference detailed tick for replay. Transient: a reload only costs one detailed tick.
var _reference: Dictionary = {}
var _replay_cap: int = Schema.MAX_EXACT_INTEGER
var _pending_stop: Dictionary = {}
var _stats: Dictionary = {}
var _call: Dictionary = {}

func _init() -> void:
	reset_time_stats()

func initialize(config: Dictionary, world_service: RefCounted, crew_adapter: RefCounted) -> Dictionary:
	var loaded := Campaign.load_profile(config)
	if not loaded.ok: return _fail(loaded.code, loaded.reason)
	var result: Dictionary = super.initialize(Campaign.base_config(config), world_service, crew_adapter)
	if not result.ok: return result
	_profile = loaded.profile
	_config = config.duplicate(true)
	_state.records.contract_version = Campaign.VERSION
	_state.records.snapshot_version = Campaign.SNAPSHOT_VERSION
	_state.records.clock.time_scale = int(_profile.start_time_scale)
	_state.records.campaign = Campaign.initial(_state.records.crew, _state.records.crew.keys()[0], _profile, 0)
	return result

func get_capabilities() -> Dictionary:
	var result: Dictionary = super.get_capabilities()
	var integration := {}
	for hook in _hooks: integration[hook.id()] = hook.integration()
	result.merge({"persistence": true, "campaign_foundation": true, "campaign_gameplay": false,
		"fast_forward": true, "medical": false, "repair_challenges": false,
		# True when this facade applies the campaign rate itself; wrappers then pass real seconds.
		"owns_time_pacing": _profile.owns_time_pacing,
		"time_integration": integration, "time_integration_mode": _integration_mode}, true)
	return result

# ---------------------------------------------------------------- registration and queries

func register_time_hook(hook: RefCounted) -> Dictionary:
	if _busy or hook == null or not hook is Hook: return _fail("invalid_state", "Register a time hook outside updates.")
	for existing in _hooks:
		if existing.id() == hook.id(): return _fail("invalid_value", "Duplicate time hook: " + hook.id())
	_hooks.append(hook)
	_reference = {}
	return _ok()

func register_boundary_handler(kind: String, handler: Callable, payload_validator: Callable = Callable()) -> Dictionary:
	## handler(state, entry) -> {ok, events, stop}. Register before loading a checkpoint that uses the kind.
	if _busy or not Schema.identifier(kind) or Scheduler.BUILTIN.has(kind) or _boundary_handlers.has(kind) or not handler.is_valid():
		return _fail("invalid_value", "Invalid or duplicate boundary kind.")
	_boundary_handlers[kind] = handler
	_boundary_validators[kind] = payload_validator
	return _ok()

func boundary_kinds() -> Dictionary:
	return _boundary_validators.duplicate()

func schedule_boundary(due_tick: int, kind: String, payload: Dictionary, phase: int = -1) -> Dictionary:
	## Outer-boundary scheduling for integration code and tests. Feature systems
	## normally schedule from inside their own command or boundary transaction.
	var guard: Dictionary = _guard()
	if not guard.ok: return guard
	if not _boundary_handlers.has(kind) or due_tick <= int(_state.records.clock.tick_index) or due_tick > Schema.MAX_EXACT_INTEGER or phase > Scheduler.MAX_PHASE:
		return _fail("invalid_value", "Schedule a registered kind at a future whole tick.")
	var checker: Callable = _boundary_validators[kind]
	if not Saves.finite_tree(payload) or (checker.is_valid() and not checker.call(payload)): return _fail("invalid_value", "Invalid boundary payload.")
	var candidate = _state.clone()
	var id := Scheduler.schedule(candidate.records.campaign.time, due_tick, kind, payload, phase)
	candidate.records.revision += 1
	_state = candidate
	state_changed.emit(get_snapshot())
	return {"ok": true, "code": "ok", "reason": "", "id": id}

func set_time_integration(mode: String) -> Dictionary:
	if _busy or mode not in ["auto", "detailed"]: return _fail("invalid_value", "Integration mode is auto or detailed.")
	_integration_mode = mode
	_reference = {}
	return _ok()

func get_calendar() -> Dictionary:
	if _state == null: return _fail("not_initialized", "Initialize the simulation first.")
	var campaign: Dictionary = _state.records.campaign
	var clock: Dictionary = _state.records.clock
	var result := Calendar.describe(campaign.calendar, int(clock.tick_index))
	result.merge({"ok": true, "rate_sim_s_per_real_s": int(campaign.time.base_rate) * int(clock.time_scale),
		"normal_rate_sim_s_per_real_s": int(campaign.time.base_rate), "player_multipliers": _profile.player_multipliers.duplicate(),
		"paused": int(clock.time_scale) == 0, "fast_forward": campaign.time.fast_forward.duplicate(true)})
	return result

func get_time_stats() -> Dictionary:
	return _stats.duplicate(true)

func reset_time_stats() -> void:
	_stats = {"advance_calls": 0, "detailed_ticks": 0, "aggregate_intervals": 0, "aggregate_ticks": 0,
		"aggregate_account_ticks": 0, "aggregate_rejections": 0, "fallback_reasons": {},
		"max_call_detailed_ticks": 0, "max_call_account_ticks": 0, "max_call_ticks": 0, "max_call_usec": 0}

# ---------------------------------------------------------------- commands

func submit_command(command: Dictionary) -> Dictionary:
	if command.get("contract_version") != Campaign.VERSION:
		return _rejected(command.get("command_id"), "unsupported_contract", "Campaign commands require 3.0.0.")
	if Commands.owns(command.get("type")): return super.submit_command(command)
	# Compatibility is internal only. Public v2 commands are rejected by this facade.
	var translated := command.duplicate(true)
	translated.contract_version = Schema.VERSION
	return super.submit_command(translated)

func _validate_command(command: Dictionary) -> Dictionary:
	return Commands.validate(command) if Commands.owns(command.get("type")) else super._validate_command(command)

func _command_supported(normalized: Dictionary) -> bool:
	# Repair challenges are not part of campaign checkpoints yet (package 6).
	if normalized.type in Repair.COMMANDS or normalized.type in Storm.COMMANDS: return false
	return Commands.owns(normalized.type) or super._command_supported(normalized)

func _apply_command(command: Dictionary, candidate: RefCounted, ledger: RefCounted) -> Dictionary:
	var ff: Dictionary = candidate.records.campaign.time.fast_forward
	var tick: int = candidate.records.clock.tick_index
	if command.type == "request_fast_forward":
		# Validated again here: the clock may have moved since the command was received.
		var target: int = command.payload.target_elapsed_s
		var data := {"target_elapsed_s": target}
		if ff.active: return _command_result(false, "invalid_state", "A fast-forward is already active; cancel it first.", data)
		if target <= tick: return _command_result(false, "invalid_value", "The target must be later than the current mission time.", data)
		candidate.records.campaign.time.fast_forward = {"active": true, "target_tick": target, "started_tick": tick,
			"command_id": command.command_id, "stop_reason": null, "stop_detail": null, "stopped_tick": null}
		data.started_elapsed_s = tick
		return _command_result(true, "ok", "", data, true, [{"type": "fast_forward_started", "entity_ids": [], "data": data.duplicate()}])
	if command.type == "cancel_fast_forward":
		if not ff.active: return _command_result(true, "ok", "", {"cancelled": false})
		return _command_result(true, "ok", "", {"cancelled": true}, true, [_stop_fast_forward(candidate, "cancelled", "")])
	var result: Dictionary = super._apply_command(command, candidate, ledger)
	if result.success and command.type == "set_time_scale" and int(command.payload.time_scale) == 0 and ff.active:
		# Pausing never advances survival time, including a requested fast-forward.
		result.events = result.events.duplicate()
		result.events.append(_stop_fast_forward(candidate, "paused", ""))
		result.mutates = true
	return result

static func _command_result(success: bool, code: String, reason: String, data: Dictionary, mutates: bool = false, events: Array = []) -> Dictionary:
	return {"success": success, "code": code, "reason": reason, "data": data, "mutates": mutates, "events": events}

static func _stop_fast_forward(state: RefCounted, reason: String, detail: String) -> Dictionary:
	var ff: Dictionary = state.records.campaign.time.fast_forward
	var tick: int = state.records.clock.tick_index
	ff.active = false
	ff.stop_reason = reason
	ff.stop_detail = detail
	ff.stopped_tick = tick
	return {"type": "fast_forward_stopped", "entity_ids": [],
		"data": {"reason": reason, "detail": detail, "elapsed_s": tick, "target_elapsed_s": ff.target_tick}}

# ---------------------------------------------------------------- public advancement

func process_pending_commands() -> void:
	if _state == null or _busy: return
	_busy = true
	var settled := _settle()
	if settled.changed: state_changed.emit(get_snapshot())
	_busy = false

func step(delta_sim_seconds: float) -> Dictionary:
	## Oracle entry point: exactly one detailed second, with full boundary processing.
	var guard: Dictionary = _guard()
	if not guard.ok: return guard
	if not is_finite(delta_sim_seconds) or delta_sim_seconds != 1.0:
		return _fail("invalid_timestep", "step requires exactly 1.0 simulated second.")
	_busy = true
	_begin_call()
	var settled := _settle()
	var changed: bool = settled.changed
	var result: Dictionary = settled.result
	if result.ok and (int(_state.records.clock.time_scale) > 0 or _state.records.campaign.time.fast_forward.active):
		result = _detailed_tick()
		if result.ok:
			changed = true
			result = _settle().result
	_end_call()
	if changed: state_changed.emit(get_snapshot())
	_busy = false
	return result

func _advance(real_delta_s: float, max_work_usec: int) -> Dictionary:
	var guard: Dictionary = _guard()
	if not guard.ok: return guard
	if not is_finite(real_delta_s) or real_delta_s < 0:
		return _fail("invalid_value", "real_delta_s must be finite and nonnegative.")
	var rate := 20.0 * float(_state.records.campaign.time.base_rate)
	# Reject unrepresentable time before changing even the command queue.
	if real_delta_s > float(Schema.MAX_EXACT_INTEGER) / rate - _state.accumulator_s:
		return _fail("invalid_value", "Elapsed time exceeds the exact clock range.")
	_busy = true
	_begin_call()
	_call.max_usec = max_work_usec
	var settled := _settle()
	var changed: bool = settled.changed
	var result: Dictionary = settled.result
	# Real time feeds the ordinary clock only. A fast-forward advances toward its
	# committed target instead and leaves the fractional accumulator untouched.
	if result.ok and not _state.records.campaign.time.fast_forward.active:
		_state.accumulator_s += real_delta_s * float(_state.records.clock.time_scale) * float(_state.records.campaign.time.base_rate)
	while result.ok:
		var clock: Dictionary = _state.records.clock
		var fast: bool = _state.records.campaign.time.fast_forward.active
		var now: int = clock.tick_index
		var target: int
		if fast: target = int(_state.records.campaign.time.fast_forward.target_tick)
		elif int(clock.time_scale) == 0 or _state.accumulator_s < 1.0: break
		else: target = now + int(minf(floorf(_state.accumulator_s), 1.0e15))
		if not _has_budget(max_work_usec): break
		var horizon: int = mini(target, Scheduler.next_due(_state.records.campaign.time)) - now
		var limit: int = int(_profile.max_ticks_per_advance)
		if limit > 0: horizon = mini(horizon, limit - int(_call.ticks))
		var done := _replay_interval(horizon)
		# The replay budget for this call is spent: yield and keep the backlog.
		if done < 0: break
		if done == 0:
			result = _detailed_tick()
			if not result.ok: break
			done = 1
		if not fast: _state.accumulator_s -= float(done)
		changed = true
		result = _settle().result
	_end_call()
	if changed: state_changed.emit(get_snapshot())
	_busy = false
	return result

func _has_budget(max_work_usec: int) -> bool:
	if int(_call.detailed) >= int(_profile.max_detailed_ticks_per_advance): return false
	if int(_profile.max_ticks_per_advance) > 0 and int(_call.ticks) >= int(_profile.max_ticks_per_advance): return false
	# Same yielding rule as the v2 budgeted path: always finish at least one unit.
	return max_work_usec <= 0 or int(_call.ticks) == 0 or Time.get_ticks_usec() - int(_call.started) < max_work_usec

func _begin_call() -> void:
	_call = {"detailed": 0, "account_ticks": 0, "ticks": 0, "max_usec": 0, "started": Time.get_ticks_usec()}

func _end_call() -> void:
	_stats.advance_calls += 1
	_stats.max_call_detailed_ticks = maxi(_stats.max_call_detailed_ticks, _call.detailed)
	_stats.max_call_account_ticks = maxi(_stats.max_call_account_ticks, _call.account_ticks)
	_stats.max_call_ticks = maxi(_stats.max_call_ticks, _call.ticks)
	_stats.max_call_usec = maxi(_stats.max_call_usec, Time.get_ticks_usec() - int(_call.started))

# ---------------------------------------------------------------- boundary processing

func _settle() -> Dictionary:
	## Finish the current whole-tick boundary. Looping until quiescent makes results
	## independent of how a wrapper splits work across frames.
	var changed := false
	for round in SETTLE_LIMIT:
		changed = _boundary() or changed
		var fired := _fire_due()
		if not fired.ok: return {"changed": changed, "result": fired}
		changed = changed or fired.changed
		changed = _check_stop() or changed
		if _pending.is_empty(): break
	return {"changed": changed, "result": _ok()}

func _fire_due() -> Dictionary:
	var changed := false
	while true:
		var time: Dictionary = _state.records.campaign.time
		if time.queue.is_empty() or int(time.queue[0].due_tick) > int(_state.records.clock.tick_index): break
		var candidate = _state.clone()
		var entry: Dictionary = candidate.records.campaign.time.queue.pop_front()
		var handler: Callable = Scheduler.builtin_handler(entry.kind) if Scheduler.BUILTIN.has(entry.kind) else _boundary_handlers.get(entry.kind, Callable())
		if not handler.is_valid(): return _fail("internal_error", "No handler for scheduled boundary: " + str(entry.kind))
		var outcome: Variant = handler.call(candidate, entry.duplicate(true))
		if not outcome is Dictionary or not outcome.get("ok", false): return _fail("internal_error", "Scheduled boundary failed: " + str(entry.kind))
		var events: Array = outcome.get("events", [])
		if candidate.records.revision >= Schema.MAX_EXACT_INTEGER or candidate.counters.event + events.size() >= Schema.MAX_EXACT_INTEGER:
			return _fail("invalid_state", "Revision or event counter exhausted.")
		var outbox: Array = []
		for event in events:
			outbox.append({"id": candidate.allocate("event"), "type": event.type, "tick_index": candidate.records.clock.tick_index,
				"entity_ids": event.get("entity_ids", []), "data": event.get("data", {})})
		candidate.records.revision += 1
		_state = candidate
		_reference = {}
		changed = true
		var stop: Variant = outcome.get("stop")
		if stop is Dictionary and _pending_stop.is_empty() and stop.get("reason") in Scheduler.STOP_REASONS:
			_pending_stop = {"reason": stop.reason, "detail": str(stop.get("detail", ""))}
		for event in outbox: game_event.emit(event.duplicate(true))
	return {"ok": true, "code": "ok", "reason": "", "changed": changed}

func _check_stop() -> bool:
	## Danger outranks a scheduled stop, which outranks reaching the target.
	var stop := _pending_stop
	_pending_stop = {}
	var ff: Dictionary = _state.records.campaign.time.fast_forward
	if not ff.active: return false
	if stop.is_empty() and int(_state.records.clock.tick_index) >= int(ff.target_tick): stop = {"reason": "target_reached", "detail": ""}
	if stop.is_empty(): return false
	var candidate = _state.clone()
	var event := _stop_fast_forward(candidate, stop.reason, stop.detail)
	event.id = candidate.allocate("event")
	event.tick_index = candidate.records.clock.tick_index
	candidate.records.revision += 1
	_state = candidate
	_reference = {}
	game_event.emit(event.duplicate(true))
	return true

# ---------------------------------------------------------------- detailed tick (oracle)

func _new_ledger(candidate: RefCounted) -> RefCounted:
	return TapeLedger.new(candidate, _content, _committed_effects, candidate.records.clock.tick_index)

func _extra_tick_phases(candidate: RefCounted, ledger: RefCounted) -> Dictionary:
	for hook in _hooks:
		var result: Dictionary = hook.detailed_interval(candidate, ledger)
		if not result.ok: return result
	return _ok()

func _detailed_tick() -> Dictionary:
	var before_signature: PackedByteArray = _reference.get("signature", PackedByteArray())
	var known: bool = _reference.get("revision", -1) == _state.records.revision
	if _integration_mode == "auto" and not known: before_signature = _signature(_state)
	var computed: Dictionary = _tick_candidate()
	if not computed.ok: return computed
	var danger := _new_danger(_state, computed.candidate)
	_commit_tick(computed)
	_stats.detailed_ticks += 1
	_call.detailed += 1
	_call.ticks += 1
	if not danger.is_empty() and _pending_stop.get("reason") != "danger": _pending_stop = {"reason": "danger", "detail": danger}
	if _integration_mode == "auto":
		var signature := _signature(_state)
		_reference = {"revision": _state.records.revision, "signature": signature,
			"tape": computed.ledger.tape, "replayable": computed.ledger.replayable and computed.events.is_empty(),
			# The discrete state must already have been steady across the reference tick.
			"steady": signature == before_signature}
	return _ok()

static func _new_danger(before: RefCounted, after: RefCounted) -> String:
	var prior := {}
	for alert in before.records.alerts: prior[alert.id] = true
	for alert in after.records.alerts:
		if not prior.has(alert.id): return "alert:" + str(alert.id)
	var ids: Array = after.crew_demand.unmet_needs.keys()
	ids.sort()
	for id in ids:
		for code in after.crew_demand.unmet_needs[id]:
			if code not in before.crew_demand.unmet_needs.get(id, []): return "unmet_need:%s:%s" % [id, code]
	return ""

static func _signature(state: RefCounted) -> PackedByteArray:
	## Everything a tick reads or writes except the clock, replayed account balances
	## and the two per-tick diagnostics derived from them.
	var records: Dictionary = state.records.duplicate(true)
	records.erase("clock")
	records.erase("revision")
	records.power.erase("battery_stored_kwh")
	for balance in records.resources.values():
		balance.erase("amount")
		balance.erase("net_rate_per_s")
		balance.erase("forecast_empty_s")
	return var_to_bytes([records, state.counters, str(state.rng.state), state.per_battery_energy.keys(), state.return_caches,
		state.prepaid_build_costs, state.power_flows, state.life_support_flows, state.crew_demand])

# ---------------------------------------------------------------- stable-interval replay

func _refuse(reason: String) -> int:
	_stats.fallback_reasons[reason] = int(_stats.fallback_reasons.get(reason, 0)) + 1
	return 0

func _replay_interval(horizon: int) -> int:
	## Returns the number of ticks committed. 0: the caller runs one detailed tick.
	## -1: this call's replay budget is spent, so the caller yields.
	## Layout: `count` replayed ticks, then one real tick that must match the reference.
	if _integration_mode != "auto": return 0
	var minimum: int = int(_profile.min_aggregate_ticks)
	if horizon < minimum: return _refuse("short_horizon")
	if _reference.get("revision", -1) != _state.records.revision: return _refuse("no_reference_tick")
	# Systems certify first, so an unmodeled interval is reported under its own name.
	var context := {"state": _state, "content": _content, "accounts": [], "deltas": {}}
	for hook in _hooks:
		var certified: Dictionary = hook.aggregate_interval(context)
		if not certified.ok: return _refuse(str(certified.reason))
	if not _reference.replayable: return _refuse("unsupported_effect_or_event")
	if not _reference.steady: return _refuse("state_changing")
	var plan := _replay_plan(_reference.tape)
	context.accounts = plan.accounts
	context.deltas = plan.deltas
	var safe: int = horizon
	for hook in _hooks:
		var transition: Dictionary = hook.next_transition(context)
		# Stop a guard band before any predicted change; the change itself runs detailed.
		if int(transition.ticks) - int(_profile.guard_ticks) < safe:
			safe = int(transition.ticks) - int(_profile.guard_ticks)
			if safe < minimum: return _refuse("transition_guard:" + str(transition.reason))
	safe = mini(safe, _replay_cap)
	var count: int = safe - 1
	if plan.active > 0:
		var allowance: int = int(_profile.max_aggregate_account_ticks_per_advance) - int(_call.account_ticks)
		if int(_call.max_usec) > 0:
			# Wall-clock yielding for interactive callers: about four account-ticks per microsecond left.
			allowance = mini(allowance, maxi(0, int(_call.max_usec) - (Time.get_ticks_usec() - int(_call.started))) * 4)
		if count > allowance / int(plan.active):
			count = allowance / int(plan.active)
			# Never stall: a call that has done nothing yet falls through to a detailed tick.
			if count + 1 < minimum: return -1 if int(_call.ticks) > 0 else _refuse("frame_budget")
	var candidate = _state.clone()
	for account in plan.accounts:
		if account.skip: continue
		if account.kind == "base":
			candidate.records.resources[account.key].amount = fold(candidate.records.resources[account.key].amount, account.ops, count)
		else:
			candidate.per_battery_energy[account.key] = fold(candidate.per_battery_energy[account.key], account.ops, count)
	candidate.records.clock.tick_index += count
	candidate.records.clock.elapsed_s = float(candidate.records.clock.tick_index)
	candidate.records.revision += count
	# Battery totals are re-derived by the real ledger, exactly as after any tick.
	TapeLedger.new(candidate, _content, {}, candidate.records.clock.tick_index)._sync_energy()
	_call.account_ticks += count * int(plan.active)
	_stats.aggregate_account_ticks += count * int(plan.active)
	var committed = _state
	_state = candidate
	var computed: Dictionary = _tick_candidate()
	_call.detailed += 1
	var proven: bool = computed.ok and computed.events.is_empty() and computed.ledger.replayable \
		and computed.ledger.tape == _reference.tape and _signature(computed.candidate) == _reference.signature
	if not proven:
		# Nothing was committed. Halve the next attempt and let a detailed tick lead.
		_state = committed
		_stats.aggregate_rejections += 1
		_replay_cap = maxi(minimum, safe / 2)
		_reference = {}
		return _refuse("verification_failed")
	_commit_tick(computed)
	_replay_cap = Schema.MAX_EXACT_INTEGER
	_reference.revision = _state.records.revision
	_stats.detailed_ticks += 1
	_stats.aggregate_intervals += 1
	_stats.aggregate_ticks += count
	_call.ticks += count + 1
	return count + 1

func _replay_plan(tape: Array) -> Dictionary:
	## Group the reference tape by account and measure each account's net change per tick.
	var index := {}
	var accounts: Array = []
	for item in tape:
		var path: String = item[1]
		if not index.has(path):
			var parts: PackedStringArray = path.split("/")
			index[path] = accounts.size()
			accounts.append({"path": path, "kind": parts[0], "key": parts[1], "ops": PackedFloat64Array(), "skip": false})
		var ops: PackedFloat64Array = accounts[index[path]].ops
		ops.append(item[2])
		ops.append(item[3])
		accounts[index[path]].ops = ops
	var plan := {"accounts": accounts, "deltas": {}, "active": 0}
	var energy := 0.0
	for account in accounts:
		var amount: float = _state.records.resources[account.key].amount if account.kind == "base" else _state.per_battery_energy[account.key]
		var delta: float = fold(amount, account.ops, 1) - amount
		plan.deltas[account.path] = delta
		if account.kind == "battery": energy += delta
		# A balance the tick leaves bit-identical stays so for the whole interval.
		account.skip = delta == 0.0
		if not account.skip: plan.active += account.ops.size() / 2
	plan.deltas["energy_total"] = energy
	return plan

static func fold(value: float, ops: PackedFloat64Array, count: int) -> float:
	## The ledger's own arithmetic, `amount - debits + credits`, once per effect per tick.
	var x := value
	match ops.size():
		2:
			var d0 := ops[0]
			var c0 := ops[1]
			for i in count: x = x - d0 + c0
		4:
			var d0 := ops[0]
			var c0 := ops[1]
			var d1 := ops[2]
			var c1 := ops[3]
			for i in count:
				x = x - d0 + c0
				x = x - d1 + c1
		6:
			var d0 := ops[0]
			var c0 := ops[1]
			var d1 := ops[2]
			var c1 := ops[3]
			var d2 := ops[4]
			var c2 := ops[5]
			for i in count:
				x = x - d0 + c0
				x = x - d1 + c1
				x = x - d2 + c2
		_:
			var size := ops.size()
			for i in count:
				for index in range(0, size, 2): x = x - ops[index] + ops[index + 1]
	return x

# ---------------------------------------------------------------- checkpoints

func export_save() -> Dictionary:
	var guard: Dictionary = _guard()
	if not guard.ok: return guard
	return Saves.encode(self)

func import_save(save_record: Dictionary) -> Dictionary:
	var guard: Dictionary = _guard()
	if not guard.ok: return guard
	_busy = true
	var decoded := Saves.decode(save_record, _world_service, _crew_adapter != null, boundary_kinds())
	if not decoded.ok:
		_busy = false
		return decoded
	# All checks and adapter construction happen off to the side. No callback/reward replay.
	_state = decoded.state
	_content = decoded.content
	_config = decoded.config
	_profile = decoded.profile
	_crew_adapter = decoded.adapter
	_journal = decoded.journal
	_pending.assign(decoded.pending)
	_next_receive_sequence = int(decoded.next_sequence)
	_committed_effects = decoded.effects
	_reference = {}
	_pending_stop = {}
	_replay_cap = Schema.MAX_EXACT_INTEGER
	state_changed.emit(get_snapshot())
	_busy = false
	return {"ok": true, "code": "ok", "reason": "", "migrated_from": decoded.migrated_from}
