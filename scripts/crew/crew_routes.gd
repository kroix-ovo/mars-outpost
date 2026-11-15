extends RefCounted
## Horizontal grid distance is authoritative; elevation is presentation only.

static func cell(point: Array) -> Array:
	return [floori(point[0]), floori(point[2])]

static func distance(a: Array, b: Array) -> float:
	var dx := float(b[0]) - float(a[0])
	var dz := float(b[2]) - float(a[2])
	return sqrt(dx * dx + dz * dz)

static func position(points: Array, metres: float) -> Array:
	for i in range(1, points.size()):
		var length := distance(points[i - 1], points[i])
		if length > 0.0 and metres < length:
			var a: Array = points[i - 1]
			var b: Array = points[i]
			return [lerpf(a[0], b[0], metres / length), lerpf(a[1], b[1], metres / length),
				lerpf(a[2], b[2], metres / length)]
		metres -= length
	return points.back().duplicate()

static func query(world: RefCounted, snapshot: Dictionary, from: Array, to: Array) -> Dictionary:
	if world == null or not world.has_method("query_route"):
		return {"reachable": false, "reason": "Routing is unavailable."}
	return world.query_route({"from_cell": from, "to_cell": to}, snapshot)

static func saved_route_clear(world: RefCounted, snapshot: Dictionary, points: Array, progress: float) -> bool:
	# A reachable detour does not make the saved route passable. Keep the route
	# fixed until an explicit recall/phase transition requests another route.
	var traversed := 0.0
	for i in range(1, points.size()):
		var length := distance(points[i - 1], points[i])
		traversed += length
		if traversed <= progress + 1e-9:
			continue
		var a := cell(points[i - 1])
		var b := cell(points[i])
		var route := query(world, snapshot, a, b)
		var direct: int = absi(a[0] - b[0]) + absi(a[1] - b[1])
		if not route.get("reachable", false) or route.distance_m > direct + 1e-9:
			return false
	return true

static func from_progress(world: RefCounted, snapshot: Dictionary, points: Array,
		metres: float, to: Array) -> Dictionary:
	var reached: Array = points[0]
	var remaining := metres
	for i in range(1, points.size()):
		var length := distance(points[i - 1], points[i])
		if remaining < length - 1e-9:
			break
		remaining = maxf(0.0, remaining - length)
		reached = points[i]
	var route := query(world, snapshot, cell(reached), to).duplicate(true)
	if route.get("reachable", false) and remaining > 1e-9:
		route.waypoints_m.push_front(position(points, metres))
		route.distance_m += remaining
	return route

# From a point between cell centers, either endpoint of that segment is a
# candidate. Charging the approach avoids oscillation at sub-meter speeds.
static func _origins(point: Array) -> Array:
	var current := cell(point)
	var choices := [current]
	var dx := float(point[0]) - (int(current[0]) + 0.5)
	var dz := float(point[2]) - (int(current[1]) + 0.5)
	if absf(dx) > 1e-9:
		choices.append([int(current[0]) + (1 if dx > 0.0 else -1), current[1]])
	elif absf(dz) > 1e-9:
		choices.append([current[0], int(current[1]) + (1 if dz > 0.0 else -1)])
	return choices

static func to_building(world: RefCounted, snapshot: Dictionary, from: Array,
		building: Dictionary, definition: Dictionary) -> Dictionary:
	var best: Dictionary = {"reachable": false}
	for offset in definition.get("entrance_cells", []):
		var x: int = offset[0]
		var z: int = offset[1]
		for turn in range(int(building.rotation_quarters)):
			var old_x := x
			x = -z
			z = old_x
		var target := [int(building.cell[0]) + x, int(building.cell[1]) + z]
		for origin in _origins(from):
			var route := query(world, snapshot, origin, target).duplicate(true)
			if route.get("reachable", false):
				var approach := distance(from, route.waypoints_m[0])
				if approach > 1e-9:
					route.waypoints_m.push_front(from.duplicate())
					route.distance_m += approach
				if not best.reachable or route.distance_m < best.distance_m - 1e-9:
					best = route
	return best
