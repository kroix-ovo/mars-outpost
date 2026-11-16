extends Control
## Modal for the simulation-owned repair challenge. It draws the session the simulation
## reports and sends inputs; it never decides success. Closing it mid-repair is only
## possible through "Abandon repair", which the simulation records as a failure.
const SHAPES = ["DIAMOND", "CIRCLE", "TRIANGLE", "SQUARE", "STAR"]
const INK := Color("#e4dfd5")
const DIM := Color("#9a958c")
const AMBER := Color("#e8962a")
const CYAN := Color("#5cc8e8")
const DANGER := Color("#ec6a52")
const OK_GREEN := Color("#7fcf7a")

var _simulation: RefCounted
var _send: Callable
var _building_id := ""
var _building_name := ""
var _crew_name := ""
var _session_id := ""
var _selected_left := -1
var _finished := false
var _title: Label
var _info: Label
var _status: Label
var _legend: Label
var _circuit: HBoxContainer
var _left_box: VBoxContainer
var _right_box: VBoxContainer
var _gauge: Control
var _lock: Button
var _slow: CheckButton
var _abandon: Button
var _close: Button
var _last_view: Dictionary = {}
# Active challenge time waiting to be sent. Nothing is dropped: it is sent in order
# in chunks of at most 0.1 s, about 20 commands a second instead of one per frame.
var _unsent_s := 0.0

func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.name = "RepairCard"
	card.custom_minimum_size = Vector2(600, 430)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.075, 0.085, 0.10, 0.98)
	box.border_color = AMBER
	box.set_border_width_all(2)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", box)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	_title = _label(column, "", 20, AMBER)
	_info = _label(column, "", 14, INK)
	_legend = _label(column, "", 14, CYAN)
	_circuit = HBoxContainer.new()
	_circuit.add_theme_constant_override("separation", 60)
	_circuit.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_circuit)
	_left_box = VBoxContainer.new()
	_right_box = VBoxContainer.new()
	_circuit.add_child(_left_box)
	_circuit.add_child(_right_box)
	_gauge = Control.new()
	_gauge.custom_minimum_size = Vector2(560, 90)
	_gauge.draw.connect(_draw_gauge)
	column.add_child(_gauge)
	_status = _label(column, "", 14, INK)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	_lock = _button(buttons, "Lock calibration (Space)", func(): _push("lock", 0.0))
	_slow = CheckButton.new()
	_slow.text = "Slow mode"
	_slow.tooltip_text = "Accessibility: the indicator and timer run at half speed."
	buttons.add_child(_slow)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_abandon = _button(buttons, "Abandon repair (counts as failed)", func(): _push("abandon", 0.0))
	_close = _button(buttons, "Close", func(): visible = false)

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 560
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 34)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func open(simulation: RefCounted, send: Callable, building_id: String, building_name: String, crew_name: String) -> void:
	_simulation = simulation
	_send = send
	_building_id = building_id
	_building_name = building_name
	_crew_name = crew_name
	_session_id = ""
	_selected_left = -1
	_finished = false
	_last_view = {}
	_title.add_theme_color_override("font_color", AMBER)
	_unsent_s = 0.0
	_circuit.set_meta("signature", "")
	visible = true
	_refresh()

func is_open() -> bool:
	return visible

func _flush_time(threshold: float) -> void:
	while _unsent_s >= threshold and _unsent_s > 0.0 and not _session_id.is_empty():
		var chunk := minf(_unsent_s, 0.1)
		_unsent_s -= chunk
		_send.call("repair_input", {"session_id": _session_id, "action": "tick", "value": chunk})

func _push(action: String, value: float) -> void:
	if _session_id.is_empty() or _finished or not _send.is_valid(): return
	# Elapsed time is delivered before the action, so ordering matches what the player saw.
	_flush_time(0.0)
	_send.call("repair_input", {"session_id": _session_id, "action": action, "value": value})
	_refresh()

func _process(delta: float) -> void:
	if not visible or _simulation == null: return
	# Challenge time only advances while this window is focused and the modal is open.
	if not _session_id.is_empty() and not _finished and get_window().has_focus():
		_unsent_s += minf(delta, 0.1) * (0.5 if _slow.button_pressed else 1.0)
		_flush_time(0.05)
	_refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed() or event.is_echo(): return
	var key := event as InputEventKey
	if key == null: return
	get_viewport().set_input_as_handled()
	if key.keycode == KEY_SPACE or key.keycode == KEY_ENTER:
		if _finished: visible = false
		else: _push("lock", 0.0)
	elif key.keycode >= KEY_1 and key.keycode <= KEY_5:
		_pick(key.keycode - KEY_1)

func _pick(index: int) -> void:
	## Keyboard path for the circuit: first number picks a lead, second picks a terminal.
	var session: Variant = _last_view.get("session")
	if session == null or session.kind != "circuit" or index >= int(session.stages): return
	if _selected_left < 0: _select_left(index)
	else: _connect(index)

func _select_left(index: int) -> void:
	_selected_left = index
	_refresh()

func _connect(slot: int) -> void:
	if _selected_left < 0: return
	var value := float(_selected_left * 10 + slot)
	_selected_left = -1
	_push("connect", value)

func _refresh() -> void:
	if _simulation == null or not _simulation.has_method("get_repair_state"): return
	var view: Dictionary = _simulation.get_repair_state()
	_last_view = view
	var session: Variant = view.get("session")
	if session != null and session.building_id == _building_id:
		_session_id = session.id
		_show_session(session)
	elif not _session_id.is_empty() or _finished:
		_finished = true
		_show_result(view)
	else:
		_title.text = "Repair: " + _building_name
		_status.text = "Waiting for the simulation to open the repair…"
	_gauge.queue_redraw()

func _show_session(session: Dictionary) -> void:
	var left: int = int(session.mistakes_allowed) - int(session.mistakes)
	_title.text = "Repair: %s" % _building_name
	_abandon.visible = true
	_close.visible = false
	_slow.visible = true
	var remaining := maxf(0.0, float(session.time_limit_s) - float(session.elapsed_s))
	var skill_text := "Engineering %d%%" % roundi(float(session.skill) * 100.0)
	if session.kind == "circuit":
		_info.text = "%s is rewiring the panel (%s: %d leads). Connect each lettered lead to the terminal with its matching shape. Click a lead then a terminal, or press its number twice (lead, then terminal)." % [_crew_name, skill_text, int(session.stages)]
		var pairs: Array[String] = []
		for index in int(session.stages): pairs.append("%s = %s" % [session.symbols[index], SHAPES[index]])
		_legend.text = "Wiring key:  " + "   ".join(pairs)
		_legend.visible = true
		_circuit.visible = true
		_gauge.visible = false
		_lock.visible = false
		_rebuild_circuit(session)
		_status.text = "Connected %d of %d · mistakes left: %d · time left: %.0f s (colony clock is frozen)" % [session.connected.size(), int(session.stages), left, remaining]
	else:
		_info.text = "%s is calibrating the tracker (%s: %d passes, window ±%d%%). Press Lock while the white marker is inside the marked band." % [_crew_name, skill_text, int(session.stages), roundi(float(session.tolerance) * 100.0)]
		_legend.visible = false
		_circuit.visible = false
		_gauge.visible = true
		_lock.visible = true
		_status.text = "Pass %d of %d · misses left: %d · time left: %.0f s (colony clock is frozen)" % [int(session.stage) + 1, int(session.stages), left, remaining]

func _rebuild_circuit(session: Dictionary) -> void:
	var signature := str([session.connected, _selected_left, session.id])
	if _circuit.get_meta("signature", "") == signature: return
	_circuit.set_meta("signature", signature)
	for box in [_left_box, _right_box]:
		for child in box.get_children(): child.queue_free()
	var used_left := {}
	var used_right := {}
	for pair in session.connected:
		used_left[int(pair[0])] = true
		used_right[int(pair[1])] = true
	for index in int(session.stages):
		var lead := _button(_left_box, "%d   Lead %s%s" % [index + 1, session.symbols[index], "   ✓" if used_left.has(index) else ""], _select_left.bind(index))
		lead.custom_minimum_size = Vector2(200, 36)
		lead.disabled = used_left.has(index)
		if index == _selected_left: lead.add_theme_color_override("font_color", AMBER)
		var owner_lead: int = int(session.right_order[index])
		var terminal := _button(_right_box, "%d   Terminal %s%s" % [index + 1, SHAPES[owner_lead], "   ✓" if used_right.has(index) else ""], _connect.bind(index))
		terminal.custom_minimum_size = Vector2(220, 36)
		terminal.disabled = used_right.has(index) or _selected_left < 0

func _draw_gauge() -> void:
	var session: Variant = _last_view.get("session")
	if session == null or session.kind != "alignment" or _finished: return
	var width := _gauge.size.x - 20.0
	var origin := Vector2(10, 30)
	_gauge.draw_rect(Rect2(origin, Vector2(width, 30)), Color(0.16, 0.18, 0.21))
	var target: float = session.targets[int(session.stage)]
	var tolerance: float = session.tolerance
	# The band is hatched as well as coloured, so it does not rely on colour alone.
	var band := Rect2(origin + Vector2((target - tolerance) * width, 0), Vector2(tolerance * 2.0 * width, 30))
	_gauge.draw_rect(band, Color(0.5, 0.81, 0.48, 0.55))
	_gauge.draw_rect(band, OK_GREEN, false, 2.0)
	var x := band.position.x
	while x < band.end.x:
		_gauge.draw_line(Vector2(x, origin.y + 30), Vector2(minf(x + 10, band.end.x), origin.y), OK_GREEN, 1.0)
		x += 10.0
	var wrapped := fposmod(float(session.phase), 2.0)
	var marker := wrapped if wrapped <= 1.0 else 2.0 - wrapped
	var marker_x := origin.x + marker * width
	_gauge.draw_line(Vector2(marker_x, origin.y - 12), Vector2(marker_x, origin.y + 42), Color.WHITE, 4.0)
	_gauge.draw_colored_polygon(PackedVector2Array([Vector2(marker_x - 8, origin.y - 14), Vector2(marker_x + 8, origin.y - 14), Vector2(marker_x, origin.y - 2)]), Color.WHITE)

func _show_result(view: Dictionary) -> void:
	var fault: Dictionary = view.get("faults", {}).get(_building_id, {})
	_legend.visible = false
	_circuit.visible = false
	_gauge.visible = false
	_lock.visible = false
	_slow.visible = false
	_abandon.visible = false
	_close.visible = true
	if fault.get("last_result") == "repaired":
		_title.text = "Repaired: %s" % _building_name
		_title.add_theme_color_override("font_color", OK_GREEN)
		_info.text = "%s restored the equipment to full condition. The result was applied once by the simulation." % _crew_name
		_status.text = "Press Close (or Space) to return to the colony."
	else:
		var retry: int = int(fault.get("locked_until_tick", 0))
		var wait: int = maxi(0, retry - int(view.get("tick_index", 0)))
		_title.text = "Repair failed: %s" % _building_name
		_title.add_theme_color_override("font_color", DANGER)
		_info.text = "The component is now fully broken and its corrective repair is locked for one mission day. Another astronaut cannot bypass the lock. Use your backup equipment or build a replacement meanwhile."
		_status.text = "Retry available in %d h %02d min of colony time. Press Close to return." % [wait / 3600, (wait % 3600) / 60]
		for injury in view.get("injuries", {}).values():
			if int(injury.started_tick) == retry - 86400:
				_info.text += "\n%s was injured by the live circuit and is off duty for %d mission day%s." % [_crew_name, int(injury.days), "" if int(injury.days) == 1 else "s"]
