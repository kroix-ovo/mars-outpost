extends RefCounted
## I use a compressed health penalty to make the shelter decision visible in a short game. These coefficients are gameplay settings, not measured radiation doses. Shelter pauses labor elsewhere in the simulation.
const DURATION_S := 7200
const UNPROTECTED_HEALTH_LOSS := 0.20
const SHELTER_FACTOR := 0.10

static func initial() -> Dictionary:
	return {"enabled":false,"status":"idle","sheltering":false,"next_tick":0,"start_tick":0,"end_tick":0}

static func sheltered(state: RefCounted) -> bool:
	return state.radiation.sheltering and state.radiation.status in ["warning", "active"]

static func tick(state: RefCounted) -> void:
	var event: Dictionary = state.radiation
	if not event.enabled: return
	var now: int = int(state.records.clock.tick_index)
	if event.status == "idle" and now >= int(event.next_tick):
		if state.storm.status in ["forecast", "active"]:
			event.next_tick = now + 300
			return
		event.status = "warning"
		event.start_tick = now + 900
		state.records.clock.time_scale = 0
	elif event.status == "warning" and now >= int(event.start_tick):
		event.status = "active"
		event.end_tick = now + DURATION_S
	elif event.status == "active":
		if now >= int(event.end_tick):
			event.status = "idle"
			event.sheltering = false
			event.next_tick = now + 172800
			return
		for member in state.records.crew.values():
			if member.status == "dead": continue
			var factor: float = SHELTER_FACTOR if sheltered(state) and member.location_kind == "base" else 1.0
			# This short demonstration reduces health but does not independently kill crew.
			member.health = maxf(0.1, float(member.health) - UNPROTECTED_HEALTH_LOSS / DURATION_S * factor)

static func command(state: RefCounted, cmd: Dictionary) -> Dictionary:
	if not state.radiation.enabled or state.radiation.status not in ["warning", "active"]:
		return {"success":false,"code":"invalid_state","reason":"No radiation event needs a response.","data":{},"mutates":false,"events":[]}
	state.radiation.sheltering = cmd.payload.enabled
	state.records.clock.time_scale = 1
	return {"success":true,"code":"ok","reason":"","data":{"sheltering":cmd.payload.enabled},"mutates":true,"events":[]}
