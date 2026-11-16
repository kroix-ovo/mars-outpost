extends Button
## I give the name and specialty separate labels so long names cannot run into the role. The portrait and labels remain one selectable crew row.
var portrait: TextureRect
var astronaut_name: Label
var specialty: Label

func _ready() -> void:
	custom_minimum_size.y = 62
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]: pad.add_theme_constant_override("margin_" + edge, 10)
	for edge in ["top", "bottom"]: pad.add_theme_constant_override("margin_" + edge, 6)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	pad.add_child(row)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(48, 48)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_theme_constant_override("separation", 3)
	row.add_child(text_column)
	astronaut_name = Label.new()
	astronaut_name.add_theme_font_size_override("font_size", 16)
	astronaut_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(astronaut_name)
	specialty = Label.new()
	specialty.add_theme_font_size_override("font_size", 14)
	specialty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_column.add_child(specialty)

func display(name_text: String, role_text: String, face: Texture2D, selected: bool) -> void:
	astronaut_name.text = name_text
	specialty.text = role_text
	portrait.texture = face
	set_pressed_no_signal(selected)
	astronaut_name.add_theme_color_override("font_color", Color("#102c32") if selected else Color("#e8f1f5"))
	specialty.add_theme_color_override("font_color", Color("#1c4148") if selected else Color("#a8becb"))
