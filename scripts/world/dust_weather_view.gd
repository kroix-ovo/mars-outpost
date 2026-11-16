extends CanvasLayer
## Quiet visual feedback for the actual committed storm. No gameplay effects or RNG.
var bridge: Node
var canvas: Control
var strength := 0.0
var drift := 0.0

func _ready() -> void:
	layer = 4 # Under the HUD at layer 5, above the rendered world.
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(canvas)
	canvas.draw.connect(_paint)

func _process(delta: float) -> void:
	if bridge == null or bridge._backend == null or not bridge._backend.has_method("get_storm_state"): return
	var storm: Dictionary = bridge._backend.get_storm_state()
	var target := 1.0 if storm.status == "active" else 0.0
	strength = move_toward(strength, target, delta * 1.2)
	var snapshot: Dictionary = bridge.snapshot
	if int(snapshot.get("clock", {}).get("time_scale", 0)) > 0 and bridge._backend.get_repair_state().session == null:
		drift += minf(delta, 0.1) * 38.0
	canvas.visible = strength > 0.001
	if canvas.visible: canvas.queue_redraw()

func _paint() -> void:
	var extent := get_viewport().get_visible_rect().size
	canvas.draw_rect(Rect2(Vector2.ZERO, extent), Color(0.68, 0.39, 0.18, 0.12 * strength))
	for i in 55:
		var x := fposmod(i * 137.0 + drift * (1.0 + (i % 4) * 0.2), extent.x + 120.0) - 60.0
		var y := fposmod(i * 89.0 + drift * 0.16, extent.y)
		canvas.draw_line(Vector2(x, y), Vector2(x + 24.0 + (i % 5) * 6, y + 3), Color(0.89, 0.66, 0.38, 0.12 * strength), 1.2, true)
