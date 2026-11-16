extends "res://scripts/simulation/resource_ledger.gd"
## The real ledger plus a recording of what one detailed tick applied. The tape lists,
## in commit order, each internal account write as [effect suffix, path, debits, credits]
## using the same sums the ledger used for `amount - debits + credits`.
var tape: Array = []
## False when the tick applied anything the replay kernel does not model.
var replayable: bool = true

func _apply(effect: Dictionary, trusted: bool) -> Dictionary:
	var id: Variant = effect.get("effect_id")
	var replayed: bool = id is String and (retained.has(id) or staged.has(id) or tick_guards.has(id))
	var result := super._apply(effect, trusted)
	if not result.ok or replayed: return result
	var prefix := "tick:%d:" % tick
	if effect.scope != "tick" or not effect.effect_id.begins_with(prefix):
		replayable = false
		return result
	var suffix: String = effect.effect_id.substr(prefix.length())
	var order: Array = []
	var sums := {}
	for side in ["debits", "credits"]:
		for path in effect[side]:
			if not sums.has(path):
				sums[path] = {"debits": 0.0, "credits": 0.0}
				order.append(path)
			sums[path][side] += float(effect[side][path])
	for path in order:
		var parts: PackedStringArray = path.split("/")
		if parts[0] in ["source", "sink", "loss"]: continue
		var base: bool = parts.size() == 2 and parts[0] == "base" and parts[1] != "energy_kwh"
		var battery: bool = parts.size() == 3 and parts[0] == "battery" and parts[2] == "energy_kwh"
		if not base and not battery: replayable = false
		tape.append([suffix, path, sums[path].debits, sums[path].credits])
	return result
