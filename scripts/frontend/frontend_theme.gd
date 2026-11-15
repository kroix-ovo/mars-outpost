extends RefCounted
## Shared look for the title screen, customizer and intro: the HUD's warm ink and amber palette
## on dark glass panels, with large type (body text never below 16 px at 1280x720).

const INK := Color("#ece6da")
const DIM := Color("#a9a296")
const AMBER := Color("#ffb347")
const AMBER_DEEP := Color("#e8962a")
const PANEL := Color(0.06, 0.07, 0.09, 0.82)
const PANEL_EDGE := Color(1, 1, 1, 0.08)


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", INK)
	for type in ["Button", "CheckBox", "OptionButton"]:
		t.set_font_size("font_size", type, 19)
		t.set_color("font_color", type, INK)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color("#1a1308"))
		t.set_color("font_disabled_color", type, Color(INK, 0.4))
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, box(Color("#1d232a", 0.92), 6, 14, 8, Color("#3a434d")))
		t.set_stylebox("hover", type, box(Color("#29313a", 0.95), 6, 14, 8, AMBER.darkened(0.15)))
		t.set_stylebox("pressed", type, box(AMBER, 6, 14, 8, AMBER))
		t.set_stylebox("focus", type, box(Color(0, 0, 0, 0), 6, 14, 8, AMBER, 2))
		t.set_stylebox("disabled", type, box(Color("#15191e", 0.9), 6, 14, 8, Color("#262c33")))
	t.set_stylebox("normal", "LineEdit", box(Color("#0f1317"), 5, 10, 6, Color("#3a434d")))
	t.set_stylebox("focus", "LineEdit", box(Color("#0f1317"), 5, 10, 6, AMBER, 2))
	t.set_font_size("font_size", "LineEdit", 20)
	t.set_color("font_color", "LineEdit", INK)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 10, 22, 18, PANEL_EDGE))
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_stylebox("slider", "HSlider", box(Color("#2a3038"), 3, 0, 3, Color(0, 0, 0, 0)))
	t.set_stylebox("grabber_area", "HSlider", box(AMBER_DEEP, 3, 0, 3, Color(0, 0, 0, 0)))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(AMBER, 3, 0, 3, Color(0, 0, 0, 0)))
	return t


static func box(color: Color, radius: int, pad_x: int, pad_y: int, border: Color = Color(0, 0, 0, 0), width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	style.border_color = border
	style.set_border_width_all(width if border.a > 0.0 else 0)
	return style


static func primary(button: Button, size: int = 22) -> void:
	## The one action the screen wants next: filled amber with dark text.
	button.add_theme_stylebox_override("normal", box(AMBER, 8, 22, 12, AMBER.lightened(0.2)))
	button.add_theme_stylebox_override("hover", box(AMBER.lightened(0.12), 8, 22, 12, Color.WHITE, 2))
	button.add_theme_stylebox_override("pressed", box(AMBER_DEEP, 8, 22, 12, AMBER))
	button.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), 8, 22, 12, Color.WHITE, 2))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, Color("#1a1308"))
	button.add_theme_font_size_override("font_size", size)


static func label(text: String, size: int = 18, color: Color = INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


static func heading(text: String, size: int = 30) -> Label:
	var node := label(text, size, Color.WHITE)
	node.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	node.add_theme_constant_override("outline_size", 6)
	return node
