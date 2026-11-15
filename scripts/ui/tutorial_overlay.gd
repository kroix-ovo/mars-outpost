extends Control
## Draws the tutorial's pulsing highlight around the current target: a live HUD control rect
## and/or a projected world point. Presentation only; never receives mouse input.

const AMBER := Color("#ffb347")

## Returns {"rects": Array[Rect2], "points": Array[{"at": Vector2, "label": String}]} in this
## control's coordinate space, re-evaluated every frame so highlights follow scrolling,
## layout changes and camera movement.
var resolver: Callable


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func current_targets() -> Dictionary:
	if not visible or not resolver.is_valid():
		return {"rects": [], "points": []}
	return resolver.call()


func _draw() -> void:
	var targets := current_targets()
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
	var color := Color(AMBER, 0.55 + 0.45 * pulse)
	for rect in targets.get("rects", []):
		var r: Rect2 = rect.grow(4.0 + 2.0 * pulse)
		draw_rect(r, Color(AMBER, 0.10 * pulse), true)
		draw_rect(r, color, false, 3.0)
		# Pointer triangle above the target.
		var tip := Vector2(r.get_center().x, r.position.y - 4.0)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-9, -13), tip + Vector2(9, -13)]), color)
	# Context (what the step talks about): a quiet ring or outline with no pointer.
	for item in targets.get("context", []):
		if item is Rect2:
			draw_rect(item.grow(3.0), Color(AMBER, 0.45), false, 2.0)
		else:
			draw_arc(item.at, 22.0, 0.0, TAU, 40, Color(AMBER, 0.5), 2.0, true)
			var label := str(item.get("label", ""))
			if not label.is_empty():
				var font := get_theme_default_font()
				draw_string(font, item.at + Vector2(-font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x * 0.5, -30), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 1, 1, 0.9))
	for point in targets.get("points", []):
		var at: Vector2 = point.at
		var radius := 20.0 + 8.0 * pulse
		draw_arc(at, radius, 0.0, TAU, 40, color, 3.0, true)
		draw_arc(at, radius * 0.45, 0.0, TAU, 24, Color(AMBER, 0.6), 2.0, true)
		var tip := at + Vector2(0, -radius - 6.0)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-10, -15), tip + Vector2(10, -15)]), color)
		var label := str(point.get("label", ""))
		if not label.is_empty():
			var font := get_theme_default_font()
			var size := 16
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var box := Rect2(tip + Vector2(-width * 0.5 - 8, -45), Vector2(width + 16, 26))
			draw_rect(box, Color(0.07, 0.08, 0.09, 0.9), true)
			draw_rect(box, color, false, 2.0)
			draw_string(font, box.position + Vector2(8, 19), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
