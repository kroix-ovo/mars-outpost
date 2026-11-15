extends RefCounted
## Tests only. Routes over the shared flat map with a controllable blockage.

const DIRS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
var blocked: Array[Vector2i] = []
var catalog: Dictionary = {}

func _cells(definition: Dictionary, key: String, base: Array, turn: int) -> Array:
	var cells: Array = []
	for offset in definition[key]:
		var point := Vector2i(offset[0], offset[1])
		for step in range(turn):
			point = Vector2i(-point.y, point.x)
		cells.append(Vector2i(base[0], base[1]) + point)
	return cells

func _occupied(snapshot: Dictionary) -> Dictionary:
	var filled := {}
	for point in blocked:
		filled[point] = true
	for b in snapshot.buildings.values():
		if b.lifecycle != "destroyed":
			for point in _cells(catalog[b.definition_id], "footprint_cells", b.cell, b.rotation_quarters):
				filled[point] = true
	return filled

func _valid(p: Vector2i, filled: Dictionary) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < 16 and p.y < 16 and not filled.has(p)

func _path(from: Vector2i, to: Vector2i, filled: Dictionary) -> Array:
	if not _valid(from, filled) or not _valid(to, filled):
		return []
	var queue: Array[Vector2i] = [from]
	var visited := {from: from}
	var i := 0
	while i < queue.size() and not visited.has(to):
		var point := queue[i]
		i += 1
		for step in DIRS:
			var next: Vector2i = point + step
			if _valid(next, filled) and not visited.has(next):
				queue.append(next)
				visited[next] = point
	if not visited.has(to):
		return []
	var points := []
	var p := to
	while true:
		points.push_front([p.x + 0.5, 0.0, p.y + 0.5])
		if p == from:
			return points
		p = visited[p]
	return []

func query_route(request: Dictionary, snapshot: Dictionary) -> Dictionary:
	var from := Vector2i(request.from_cell[0], request.from_cell[1])
	var to := Vector2i(request.to_cell[0], request.to_cell[1])
	var filled := _occupied(snapshot)
	var points := _path(from, to, filled)
	if points.is_empty():
		return {"reachable": false, "code": "route_unreachable", "reason": "No route across the fixture grid.",
			"route_id": null, "distance_m": 0.0, "waypoints_m": []}
	var cells := filled.keys()
	cells.sort()
	return {"reachable": true, "code": "ok", "reason": "",
		"route_id": ("fixture_flat_16:%s:%s:%s" % [str(from), str(to), str(cells)]).sha256_text(),
		"distance_m": float(points.size() - 1), "waypoints_m": points}

func validate_placement(request: Dictionary, snapshot: Dictionary) -> Dictionary:
	var failure := {"valid": false, "code": "placement_blocked", "reason": "Choose an open cell with an entrance.",
		"occupied_cells": [], "entrance_cells": []}
	if not catalog.has(request.definition_id):
		return failure
	var definition: Dictionary = catalog[request.definition_id]
	var filled := _occupied(snapshot)
	var cells := _cells(definition, "footprint_cells", request.cell, request.rotation_quarters)
	var entries := _cells(definition, "entrance_cells", request.cell, request.rotation_quarters)
	for p in cells:
		if not _valid(p, filled) or p == Vector2i(2, 8):
			return failure
		for site in snapshot.sites.values():
			if p == Vector2i(site.cell[0], site.cell[1]):
				return failure
		filled[p] = true
	var accessible := false
	for p in entries:
		accessible = accessible or not _path(Vector2i(2, 8), p, filled).is_empty()
	if not accessible:
		return failure
	failure.merge({"valid": true, "code": "ok", "reason": "",
		"occupied_cells": cells.map(func(p: Vector2i): return [p.x, p.y]),
		"entrance_cells": entries.map(func(p: Vector2i): return [p.x, p.y])}, true)
	return failure
