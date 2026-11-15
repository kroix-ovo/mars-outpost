extends Control
## Small vector icons drawn with primitives so the HUD needs no font glyphs or image assets.

var kind := "dot"
var color := Color(0.88, 0.86, 0.82)


static func make(icon_kind: String, icon_color: Color, size_px: float = 16.0) -> Control:
	var icon: Control = load("res://scripts/ui/hud_icon.gd").new()
	icon.kind = icon_kind
	icon.color = icon_color
	icon.custom_minimum_size = Vector2(size_px, size_px)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


func set_color(value: Color) -> void:
	color = value
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var w := maxf(1.5, s * 0.11)
	match kind:
		"pause":
			draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.36), Vector2(s * 0.2, s * 0.72)), color)
			draw_rect(Rect2(c + Vector2(s * 0.1, -s * 0.36), Vector2(s * 0.2, s * 0.72)), color)
		"play":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.28, -s * 0.36), c + Vector2(s * 0.36, 0), c + Vector2(-s * 0.28, s * 0.36)]), color)
		"oxygen":
			draw_arc(c, s * 0.36, 0, TAU, 20, color, w, true)
			draw_circle(c + Vector2(s * 0.12, -s * 0.1), s * 0.1, color)
		"water":
			var drop := PackedVector2Array([c + Vector2(0, -s * 0.42)])
			for i in 13:
				var a := PI * i / 12.0
				drop.append(c + Vector2(cos(a) * s * 0.28, s * 0.1 + sin(a) * s * 0.28))
			draw_colored_polygon(drop, color)
		"power":
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.08, -s * 0.44), c + Vector2(-s * 0.26, s * 0.06),
				c + Vector2(-s * 0.02, s * 0.06), c + Vector2(-s * 0.1, s * 0.44), c + Vector2(s * 0.26, -s * 0.08), c + Vector2(s * 0.02, -s * 0.08)]), color)
		"battery":
			draw_rect(Rect2(c + Vector2(-s * 0.4, -s * 0.22), Vector2(s * 0.72, s * 0.44)), color, false, w)
			draw_rect(Rect2(c + Vector2(s * 0.34, -s * 0.1), Vector2(s * 0.08, s * 0.2)), color)
			draw_rect(Rect2(c + Vector2(-s * 0.3, -s * 0.12), Vector2(s * 0.34, s * 0.24)), color)
		"co2":
			for p in [Vector2(-0.16, 0.06), Vector2(0.12, 0.08), Vector2(-0.02, -0.12)]:
				draw_circle(c + p * s, s * 0.2, color)
		"food":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.42), c + Vector2(s * 0.3, -s * 0.05),
				c + Vector2(0, s * 0.38), c + Vector2(-s * 0.3, -s * 0.05)]), color)
			draw_line(c + Vector2(0, -s * 0.3), c + Vector2(0, s * 0.42), Color(0, 0, 0, 0.45), w * 0.7, true)
		"alert":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.42), c + Vector2(s * 0.42, s * 0.36), c + Vector2(-s * 0.42, s * 0.36)]), color)
			draw_rect(Rect2(c + Vector2(-s * 0.05, -s * 0.16), Vector2(s * 0.1, s * 0.3)), Color(0.08, 0.08, 0.09))
			draw_rect(Rect2(c + Vector2(-s * 0.05, s * 0.2), Vector2(s * 0.1, s * 0.09)), Color(0.08, 0.08, 0.09))
		"crew":
			draw_circle(c + Vector2(0, -s * 0.2), s * 0.17, color)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.32, s * 0.42), c + Vector2(-s * 0.24, s * 0.04),
				c + Vector2(s * 0.24, s * 0.04), c + Vector2(s * 0.32, s * 0.42)]), color)
		"clock":
			draw_arc(c, s * 0.38, 0, TAU, 20, color, w, true)
			draw_line(c, c + Vector2(0, -s * 0.24), color, w, true)
			draw_line(c, c + Vector2(s * 0.18, 0), color, w, true)
		"sound":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.38, -s * 0.12), c + Vector2(-s * 0.16, -s * 0.12),
				c + Vector2(s * 0.08, -s * 0.36), c + Vector2(s * 0.08, s * 0.36), c + Vector2(-s * 0.16, s * 0.12), c + Vector2(-s * 0.38, s * 0.12)]), color)
			draw_arc(c + Vector2(s * 0.08, 0), s * 0.26, -0.8, 0.8, 8, color, w, true)
		_:
			draw_circle(c, s * 0.22, color)
