extends RefCounted
## Built-in hooks for the systems the campaign facade currently runs. They only
## choose how long a stable interval may be; the facade still proves every interval
## by running the real tick at its end and comparing it with the reference tick.
const Hook = preload("res://scripts/campaign/campaign_time_hook.gd")

static func builtin() -> Array:
	return [LedgerMargins.new(), Power.new(), LifeSupport.new(), CrewDemand.new(), CrewActivity.new()]

class LedgerMargins extends Hook:
	## Reserve exhaustion and storage/battery saturation for every replayed account.
	func id() -> String: return "ledger_margins"
	func integration() -> String: return "aggregate"
	func aggregate_interval(_context: Dictionary) -> Dictionary: return {"ok": true, "reason": ""}
	func next_transition(context: Dictionary) -> Dictionary:
		var state: RefCounted = context.state
		var best := NO_LIMIT
		var reason := ""
		var energy_debit := 0.0
		for account in context.accounts:
			var amount: float
			var reserved := 0.0
			var capacity: Variant
			if account.kind == "base":
				var balance: Dictionary = state.records.resources[account.key]
				amount = balance.amount
				reserved = balance.reserved
				capacity = balance.capacity
			else:
				amount = state.per_battery_energy[account.key]
				var building: Dictionary = state.records.buildings[account.key]
				capacity = float(context.content.buildings[building.definition_id].storage_capacity.get("energy_kwh", 0.0)) if building.lifecycle == "commissioned" else 0.0
			# Lowest and highest point reached inside one tick, relative to its start.
			var ops: PackedFloat64Array = account.ops
			var offset := 0.0
			var low := 0.0
			var high := 0.0
			var largest_debit := 0.0
			var largest_credit := 0.0
			for index in range(0, ops.size(), 2):
				largest_debit = maxf(largest_debit, ops[index])
				largest_credit = maxf(largest_credit, ops[index + 1])
				low = minf(low, offset - ops[index])
				offset += ops[index + 1] - ops[index]
				high = maxf(high, offset)
				if account.kind == "battery": energy_debit += ops[index]
			var delta: float = context.deltas[account.path]
			var ticks := NO_LIMIT
			if delta < 0.0:
				ticks = Hook.ticks_until_cross(amount + low - reserved - largest_debit, delta, 0.0)
				if amount + low - reserved - largest_debit <= 0.0: ticks = 0
			elif delta > 0.0 and capacity != null:
				ticks = Hook.ticks_until_cross(float(capacity) - amount - high - largest_credit, -delta, 0.0)
				if float(capacity) - amount - high - largest_credit <= 0.0: ticks = 0
			if ticks < best:
				best = ticks
				reason = ("reserve_exhaustion:" if delta < 0.0 else "storage_saturation:") + account.path
		# Reserved base energy cannot be spent even while individual batteries hold charge.
		var energy: Dictionary = state.records.resources.energy_kwh
		var energy_delta: float = context.deltas.get("energy_total", 0.0)
		if energy_delta < 0.0 and energy.reserved > 0.0:
			var spendable: float = energy.amount - energy.reserved - energy_debit
			var ticks := 0 if spendable <= 0.0 else Hook.ticks_until_cross(spendable, energy_delta, 0.0)
			if ticks < best:
				best = ticks
				reason = "reserve_exhaustion:energy_kwh"
		return {"ticks": best, "reason": reason}

class Power extends Hook:
	func id() -> String: return "power"
	func integration() -> String: return "aggregate"
	func aggregate_interval(context: Dictionary) -> Dictionary:
		# Event modifiers have tick-indexed start/end boundaries; none are installed yet.
		if not context.state.records.active_events.is_empty(): return {"ok": false, "reason": "power:event_modifier"}
		return {"ok": true, "reason": ""}
	func next_transition(context: Dictionary) -> Dictionary:
		var power: Dictionary = context.state.records.power
		var delta: float = context.deltas.get("energy_total", 0.0)
		if power.battery_capacity_kwh <= 0.0: return {"ticks": NO_LIMIT, "reason": ""}
		var threshold: float = context.content.science.alerts.battery_low_fraction * power.battery_capacity_kwh
		return {"ticks": Hook.ticks_until_cross(power.battery_stored_kwh, delta, threshold), "reason": "alert_threshold:battery_low"}

class LifeSupport extends Hook:
	func id() -> String: return "life_support"
	func integration() -> String: return "aggregate"
	func aggregate_interval(_context: Dictionary) -> Dictionary: return {"ok": true, "reason": ""}
	func next_transition(context: Dictionary) -> Dictionary:
		var resources: Dictionary = context.state.records.resources
		var alerts: Dictionary = context.content.science.alerts
		var co2 := Hook.ticks_until_cross(resources.co2_kg.amount, context.deltas.get("base/co2_kg", 0.0), alerts.co2_high_kg)
		# low_oxygen: accessible oxygen <= forecast window * consumption (or depleted).
		var oxygen_delta: float = context.deltas.get("base/oxygen_kg", 0.0)
		var accessible: float = resources.oxygen_kg.amount - resources.oxygen_kg.reserved
		var oxygen := Hook.ticks_until_cross(accessible, oxygen_delta, alerts.low_oxygen_forecast_s * maxf(0.0, -oxygen_delta))
		if co2 <= oxygen: return {"ticks": co2, "reason": "alert_threshold:co2_high"}
		return {"ticks": oxygen, "reason": "alert_threshold:low_oxygen"}

class CrewDemand extends Hook:
	## Metabolic demand is constant per tick while every reserve covers it; the
	## ledger-margin hook bounds that, so this hook adds no further transition.
	func id() -> String: return "crew_demand"
	func integration() -> String: return "aggregate"
	func aggregate_interval(_context: Dictionary) -> Dictionary: return {"ok": true, "reason": ""}

class CrewActivity extends Hook:
	## Travel follows routes and labor/EVA phases complete at specific ticks. Those
	## are not modeled as stable flows: any active crew work keeps detailed stepping.
	func id() -> String: return "crew_activity"
	func integration() -> String: return "detailed_fallback"
	func aggregate_interval(context: Dictionary) -> Dictionary:
		var records: Dictionary = context.state.records
		for member in records.crew.values():
			if member.status in ["travelling", "working", "eva"] or member.location_kind != "base":
				return {"ok": false, "reason": "crew_activity:" + str(member.status)}
		for trip in records.expeditions.values():
			if trip.status not in ["completed", "failed"]: return {"ok": false, "reason": "crew_activity:expedition"}
		if not context.state.return_caches.is_empty(): return {"ok": false, "reason": "crew_activity:return_cache"}
		return {"ok": true, "reason": ""}
