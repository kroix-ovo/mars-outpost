extends RefCounted
## Shared by the launch estimate and authoritative one-second metabolism.
static func modifier(snapshot: Dictionary, target: String) -> float:
	var value := 1.0
	var ids: Array = snapshot.active_events.keys()
	ids.sort()
	for id in ids:
		var event: Dictionary = snapshot.active_events[id]
		var tick: int = snapshot.clock.tick_index
		if not (event.starts_tick <= tick and tick < event.ends_tick):
			continue
		for item in event.modifiers:
			if item.target == target:
				value *= float(item.factor)
	return value

static func rate(snapshot: Dictionary, phase: String, store: String, rates: Dictionary, policy: Dictionary) -> float:
	var overrides: Dictionary = policy.get("phase_rates_per_s", {}).get(phase, {})
	return float(overrides.get(store, rates[store])) * modifier(snapshot, "eva_" + store)
