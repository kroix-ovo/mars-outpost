extends Control
## Crisp native playback geometry; never font glyphs or emoji.
var triangles := 1
var ink := Color("#e8f1f5")

func _draw() -> void:
	var center := size * 0.5
	if triangles == 0:
		draw_rect(Rect2(center + Vector2(-7, -8), Vector2(5, 16)), ink)
		draw_rect(Rect2(center + Vector2(2, -8), Vector2(5, 16)), ink)
		return
	var width := 11.0
	var gap := 2.0
	var start := center.x - (triangles * width + (triangles - 1) * gap) * 0.5
	for i in triangles:
		var x := start + i * (width + gap)
		draw_colored_polygon(PackedVector2Array([Vector2(x, center.y - 8), Vector2(x + width, center.y), Vector2(x, center.y + 8)]), ink)
