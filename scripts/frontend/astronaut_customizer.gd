extends Control
## "Design your astronaut": a live 3D preview on the left and every appearance option on the
## right. Emits finished(look) or cancelled(). Presentation only; the look is saved by the caller.

signal finished(look: Dictionary)
signal cancelled

const Look := preload("res://scripts/crew/astronaut_look.gd")
const Figure := preload("res://scripts/crew/astronaut_figure.gd")
const UI := preload("res://scripts/frontend/frontend_theme.gd")

const ROWS := [
	{"group": "skin", "title": "Skin tone", "kind": "swatch"},
	{"group": "hair_style", "title": "Hair", "kind": "step"},
	{"group": "hair_color", "title": "Eyebrows and facial hair colour", "kind": "swatch"},
	{"group": "eye_color", "title": "Eyes", "kind": "swatch"},
	{"group": "facial_hair", "title": "Facial hair", "kind": "step"},
	{"group": "glasses", "title": "Glasses", "kind": "step"},
	{"group": "build", "title": "Build", "kind": "segment"},
	{"group": "height", "title": "Height", "kind": "segment"},
	{"group": "suit", "title": "Suit", "kind": "swatch"},
	{"group": "accent", "title": "Trim and gloves", "kind": "swatch"},
]

var look: Dictionary = Look.default_look()
var figure: Node3D
var name_edit: LineEdit
var continue_button: Button
var randomize_button: Button
var back_button: Button
var preview: SubViewportContainer
var _value_labels := {}
var _swatches := {}
var _segments := {}
var _turn := 0.0
var _dragging := false
var _rng := RandomNumberGenerator.new()
var _pose_until := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UI.build()
	_rng.randomize()
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.035, 0.05, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	margin.add_child(page)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	head.add_child(UI.heading("Design your astronaut", 34))
	head.add_child(UI.label("You are the mission commander. Make them look like you, or like anyone you want.", 18, UI.DIM))
	page.add_child(head)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	page.add_child(body)
	body.add_child(_build_preview())
	body.add_child(_build_options())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	page.add_child(footer)
	back_button = Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(func(): cancelled.emit())
	footer.add_child(back_button)
	randomize_button = Button.new()
	randomize_button.text = "Surprise me"
	randomize_button.tooltip_text = "Pick a random look. Your name stays."
	randomize_button.pressed.connect(randomize_look)
	footer.add_child(randomize_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	continue_button = Button.new()
	continue_button.text = "Meet the crew  ›"
	UI.primary(continue_button)
	continue_button.pressed.connect(_finish)
	footer.add_child(continue_button)
	set_look(look)


func set_look(new_look: Dictionary) -> void:
	look = Look.sanitize(new_look)
	if name_edit != null and name_edit.text != look.name:
		name_edit.text = look.name
	_refresh()


func randomize_look() -> void:
	var keep: String = look.name
	var next := Look.random_look(_rng)
	next.name = keep
	set_look(next)
	_pose_until = (figure.anim_time if figure != null else 0.0) + 1.6
	if figure != null:
		figure.mode = "cheer"


func choose(group: String, id: String) -> void:
	look[group] = Look.option(group, id).id
	_refresh()


func step(group: String, delta: int) -> void:
	var list: Array = Look.GROUPS[group]
	var index := posmod(Look.index_of(group, look[group]) + delta, list.size())
	choose(group, list[index].id)


func _finish() -> void:
	look.name = Look.clean_name(name_edit.text)
	if look.name.is_empty():
		name_edit.grab_focus()
		name_edit.placeholder_text = "Type a name first"
		return
	finished.emit(Look.sanitize(look))


func _refresh() -> void:
	for group in _value_labels:
		_value_labels[group].text = Look.option(group, look[group]).label
	for group in _swatches:
		for button in _swatches[group]:
			var on: bool = button.get_meta("id") == look[group]
			button.add_theme_stylebox_override("normal", _swatch_style(button.get_meta("color"), on))
			button.add_theme_stylebox_override("hover", _swatch_style(button.get_meta("color"), true))
			button.add_theme_stylebox_override("pressed", _swatch_style(button.get_meta("color"), true))
			button.button_pressed = on
	for group in _segments:
		for button in _segments[group]:
			button.set_pressed_no_signal(button.get_meta("id") == look[group])
	if continue_button != null:
		continue_button.disabled = Look.clean_name(name_edit.text).is_empty()
	if figure != null:
		var keep := look.duplicate()
		keep.name = Look.clean_name(name_edit.text) if name_edit != null else look.name
		figure.apply_look(keep)


func _build_preview() -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.0
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	panel.add_child(stack)
	preview = SubViewportContainer.new()
	preview.stretch = true
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size = Vector2(300, 300)
	preview.gui_input.connect(_on_preview_input)
	preview.mouse_default_cursor_shape = Control.CURSOR_DRAG
	stack.add_child(preview)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.transparent_bg = false
	preview.add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("#241815")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.72, 0.68, 0.72)
	env.environment.ambient_light_energy = 0.65
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	viewport.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	key.rotation_degrees = Vector3(-35, 35, 0)
	viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.6
	rim.light_color = Color(1.0, 0.6, 0.4)
	rim.rotation_degrees = Vector3(-20, 200, 0)
	viewport.add_child(rim)
	var floor_disc := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.75
	disc.height = 0.06
	floor_disc.mesh = disc
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#8a4a2c")
	floor_material.roughness = 1.0
	floor_disc.material_override = floor_material
	floor_disc.position = Vector3(0, -0.03, 0)
	viewport.add_child(floor_disc)
	figure = Figure.new()
	figure.name = "Preview"
	viewport.add_child(figure)
	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0, 1.0, 3.6)
	viewport.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0, 0.82, 0), Vector3.UP)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tools.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(tools)
	var left := Button.new()
	left.text = "‹ Turn"
	left.pressed.connect(func(): _turn -= 0.6)
	tools.add_child(left)
	var wave := Button.new()
	wave.text = "Wave"
	wave.pressed.connect(func():
		figure.mode = "wave"
		_pose_until = figure.anim_time + 2.4)
	tools.add_child(wave)
	var right := Button.new()
	right.text = "Turn ›"
	right.pressed.connect(func(): _turn += 0.6)
	tools.add_child(right)
	stack.add_child(_centered(UI.label("Drag the astronaut to turn them around.", 16, UI.DIM)))
	return panel


func _build_options() -> Control:
	## Two columns of options (face and hair; body and suit) under a full-width name field.
	## Each option shows its title and current choice above the control.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.3
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	name_row.add_child(UI.label("Name", 18, UI.DIM))
	name_edit = LineEdit.new()
	name_edit.max_length = Look.MAX_NAME_LENGTH
	name_edit.placeholder_text = "Your astronaut's name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(_text: String):
		look.name = Look.clean_name(name_edit.text)
		if continue_button != null:
			continue_button.disabled = Look.clean_name(name_edit.text).is_empty())
	name_edit.text_submitted.connect(func(_text: String): _finish())
	name_row.add_child(name_edit)
	list.add_child(name_row)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 22)
	list.add_child(columns)
	var half := ROWS.size() / 2
	for c in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 10)
		columns.add_child(column)
		for i in range(c * half, (c + 1) * half):
			column.add_child(_option_row(ROWS[i]))
	return panel


func _option_row(row: Dictionary) -> Control:
	var group: String = row.group
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)
	var top := HBoxContainer.new()
	block.add_child(top)
	var title := UI.label(row.title, 17, UI.DIM)
	title.name = str(row.group) + "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(title)
	var value := UI.label("", 17, Color.WHITE)
	_value_labels[group] = value
	top.add_child(value)
	match str(row.kind):
		"swatch":
			var flow := HFlowContainer.new()
			flow.add_theme_constant_override("h_separation", 4)
			flow.add_theme_constant_override("v_separation", 5)
			_swatches[group] = []
			for entry in Look.GROUPS[group]:
				var swatch := Button.new()
				swatch.name = "%s_%s" % [group, entry.id]
				swatch.custom_minimum_size = Vector2(25, 25)
				swatch.toggle_mode = true
				swatch.tooltip_text = entry.label
				swatch.focus_mode = Control.FOCUS_ALL
				swatch.set_meta("id", entry.id)
				swatch.set_meta("color", entry.color)
				swatch.pressed.connect(choose.bind(group, entry.id))
				flow.add_child(swatch)
				_swatches[group].append(swatch)
			block.add_child(flow)
		"step":
			value.visible = false
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 6)
			var prev := Button.new()
			prev.text = "‹"
			prev.custom_minimum_size = Vector2(42, 0)
			prev.pressed.connect(step.bind(group, -1))
			line.add_child(prev)
			var shown := UI.label("", 18, Color.WHITE)
			shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			shown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_value_labels[group] = shown
			line.add_child(shown)
			var next := Button.new()
			next.text = "›"
			next.custom_minimum_size = Vector2(42, 0)
			next.pressed.connect(step.bind(group, 1))
			line.add_child(next)
			block.add_child(line)
		"segment":
			value.visible = false
			var buttons := HBoxContainer.new()
			buttons.add_theme_constant_override("separation", 6)
			_segments[group] = []
			for entry in Look.GROUPS[group]:
				var option := Button.new()
				option.text = entry.label
				option.toggle_mode = true
				option.add_theme_font_size_override("font_size", 17)
				option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				option.set_meta("id", entry.id)
				option.pressed.connect(choose.bind(group, entry.id))
				buttons.add_child(option)
				_segments[group].append(option)
			block.add_child(buttons)
	return block


func _swatch_style(color: Color, on: bool) -> StyleBoxFlat:
	var style := UI.box(color, 13, 0, 0, Color.WHITE if on else Color(0, 0, 0, 0.5), 3 if on else 1)
	if on:
		style.expand_margin_left = 2
		style.expand_margin_right = 2
		style.expand_margin_top = 2
		style.expand_margin_bottom = 2
	return style


func _centered(node: Control) -> Control:
	var box := CenterContainer.new()
	box.add_child(node)
	return box


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_turn += event.relative.x * 0.012


func _process(delta: float) -> void:
	if figure == null:
		return
	figure.rotation.y = lerp_angle(figure.rotation.y, _turn, 1.0 - exp(-10.0 * delta))
	if figure.mode != "idle" and figure.anim_time > _pose_until:
		figure.mode = "idle"
