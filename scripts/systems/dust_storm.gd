extends RefCounted
## I roll storms against simulation time and the seeded RNG. I modify solar generation and optional farm load without overwriting the player's own equipment settings.
const COMMANDS = ["set_storm_response", "start_storm_practice"]
const RESPONSES = ["keep_farm", "save_power"]
const SOLAR_FACTOR := 0.25
const CHECK_S := 1800
const CHANCE := 0.25
const LEAD_S := 900
const MIN_DURATION_S := 7200
const MAX_DURATION_S := 14400
const COOLDOWN_S := 43200

static func initial() -> Dictionary:
	return {"enabled": false, "status": "idle", "next_check_tick": null, "arrival_tick": null, "end_tick": null,
		"cooldown_until_tick": null, "duration_s": null, "response": "keep_farm", "practice": false, "count": 0}

static func solar_factor(state: RefCounted, definition_id: String) -> float:
	## Only solar equipment is affected; other generators keep their output.
	return SOLAR_FACTOR if state.storm.status == "active" and definition_id.begins_with("solar_array") else 1.0

static func sheds(state: RefCounted, definition_id: String) -> bool:
	## Temporary policy: the player's own enabled/disabled settings are never touched.
	return state.storm.status == "active" and state.storm.response == "save_power" and definition_id.begins_with("greenhouse")

static func tick(state: RefCounted) -> void:
	var storm: Dictionary = state.storm
	if not storm.enabled: return
	var now: int = state.records.clock.tick_index
	if storm.status == "idle" and state.radiation.status in ["warning", "active"]:
		storm.next_check_tick = now + CHECK_S
		return
	match storm.status:
		"idle":
			if storm.next_check_tick == null: storm.next_check_tick = now + CHECK_S
			if storm.practice or now >= int(storm.next_check_tick):
				var chosen: bool = storm.practice or state.rng.randf() < CHANCE
				if not chosen:
					storm.next_check_tick = now + CHECK_S
					return
				storm.duration_s = state.rng.randi_range(MIN_DURATION_S, MAX_DURATION_S)
				storm.status = "forecast"
				storm.practice = false
				storm.arrival_tick = now + LEAD_S
				storm.count = int(storm.count) + 1
				# One pause so the warning can be read at any speed. Time only counts while running.
				state.records.clock.time_scale = 0
		"forecast":
			if now >= int(storm.arrival_tick):
				storm.status = "active"
				storm.end_tick = now + int(storm.duration_s)
		"active":
			if now >= int(storm.end_tick):
				storm.status = "cooldown"
				storm.response = "keep_farm"
				storm.cooldown_until_tick = now + COOLDOWN_S
		"cooldown":
			if storm.practice or now >= int(storm.cooldown_until_tick):
				storm.status = "idle"
				storm.next_check_tick = now + (0 if storm.practice else CHECK_S)

static func command(state: RefCounted, cmd: Dictionary) -> Dictionary:
	var storm: Dictionary = state.storm
	if not storm.enabled: return _result(false, "module_unavailable", "Dust storms are not enabled in this colony.", {})
	if cmd.type == "set_storm_response":
		var response: String = cmd.payload.response
		if storm.status not in ["forecast", "active"]: return _result(false, "invalid_state", "There is no storm to respond to.", {"response": response})
		var changed: bool = storm.response != response
		storm.response = response
		return _result(true, "ok", "", {"response": response}, changed)
	if storm.status not in ["idle", "cooldown"]: return _result(false, "invalid_state", "A storm is already forecast or active.", {})
	storm.practice = true
	return _result(true, "ok", "", {"practice": true}, true)

static func _result(success: bool, code: String, reason: String, data: Dictionary, mutates: bool = false) -> Dictionary:
	return {"success": success, "code": code, "reason": reason, "data": data, "mutates": mutates, "events": []}
