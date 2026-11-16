extends RefCounted
## I keep this layer responsible for presentation and shortcuts. Each primary action still goes through the existing command path; hiding a panel must not change the colony.
const Icon = preload("res://scripts/ui/hud_icon.gd")
const PlaybackIcon = preload("res://scripts/ui/playback_icon.gd")
const Figure = preload("res://scripts/crew/astronaut_figure.gd")
const CrewLooks = preload("res://scripts/crew/crew_looks.gd")
const CrewRow = preload("res://scripts/ui/crew_roster_row.gd")
const INK := Color("#e8f1f5")
const MUTED := Color("#a8becb")
const TEAL := Color("#64d8ba")
const PAPER := Color("#182a36")
var hud: Control
var dock: PanelContainer
var transport: PanelContainer
var nav: Dictionary = {}
var action: Button
var mission_title: Label
var drawer_title: Label
var progress: ProgressBar
var _last_revision := -1
var _last_tab := -1
var _catalog_initialized := false
var playback_icons: Dictionary = {}
var _profile := ""
var portraits: Dictionary = {}
var _last_placing := false
var crew_rows: Dictionary = {}
var roster: VBoxContainer
var radiation_choices: HBoxContainer

func _init(owner_hud: Control) -> void:
	hud = owner_hud

static func surface(color: Color = PAPER, radius: int = 14, padding: int = 14) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(padding)
	box.shadow_color = Color(0.06, 0.16, 0.2, 0.16)
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 4)
	return box

static func button_style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(9)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	return box

func install() -> void:
	var t: Theme = hud.theme
	t.set_stylebox("panel", "PanelContainer", surface())
	t.set_stylebox("panel", "ItemList", button_style(Color("#10212b")))
	for kind in ["Button", "OptionButton"]:
		t.set_stylebox("normal", kind, button_style(Color("#263e4d")))
		t.set_stylebox("hover", kind, button_style(Color("#355766")))
		t.set_stylebox("pressed", kind, button_style(TEAL))
		t.set_stylebox("hover_pressed", kind, button_style(TEAL.lightened(0.08)))
		t.set_stylebox("disabled", kind, button_style(Color("#203340")))
		t.set_color("font_color", kind, INK)
		t.set_color("font_hover_color", kind, INK)
		t.set_color("font_pressed_color", kind, Color("#102c32"))
		t.set_color("font_hover_pressed_color", kind, Color("#102c32"))
		t.set_color("font_disabled_color", kind, Color("#9ab0bc"))
		var focus := button_style(Color(0, 0, 0, 0))
		focus.border_color = TEAL
		focus.set_border_width_all(2)
		t.set_stylebox("focus", kind, focus)
	t.set_stylebox("selected", "ItemList", button_style(Color("#275e57")))
	t.set_stylebox("selected_focus", "ItemList", button_style(Color("#275e57")))
	t.set_stylebox("hovered", "ItemList", button_style(Color("#2b4656")))
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", INK)
	t.set_constant("v_separation", "ItemList", 8)
	t.set_stylebox("normal", "LineEdit", button_style(Color("#10212b")))
	t.set_stylebox("focus", "LineEdit", button_style(Color("#244b4a")))
	t.set_color("font_color", "LineEdit", INK)
	t.set_stylebox("panel", "TooltipPanel", surface(Color("#10212b"), 8, 10))
	t.set_color("font_color", "TooltipLabel", Color.WHITE)
	hud._crew.fixed_icon_size = Vector2i(48, 48)
	hud._crew.max_text_lines = 2
	roster = VBoxContainer.new()
	roster.add_theme_constant_override("separation", 6)
	var crew_body: Control = hud._crew.get_parent()
	crew_body.add_child(roster)
	crew_body.move_child(roster, hud._crew.get_index())
	hud._crew.visible = false
	hud._alert_chip.custom_minimum_size.x = 180
	hud._alerts.custom_minimum_size.x = 150
	hud._alerts.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	hud._alerts.autowrap_mode = TextServer.AUTOWRAP_OFF
	for chip in hud._chips.values():
		var hit_area: Control = chip.label.get_parent()
		hit_area.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit_area.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				hud._open_tab("Systems"))
	hud._crew.add_theme_constant_override("icon_margin", 10)
	hud._crew_hint.text = "Click to select · Shift adds crew"
	hud._crew_hint.add_theme_font_size_override("font_size", 13)
	hud._crew_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hud._mission_hint.visible = false
	hud._crew_text.add_theme_font_size_override("font_size", 14)
	hud._tabs.tabs_visible = false
	hud._drawer_open = false
	hud._crew_card.visible = false
	hud._inspect_section.visible = false
	hud._placement_section.visible = true
	var outer: Control = hud._drawer.get_child(0)
	var header: Control = hud._drawer_toggle.get_parent()
	for child in header.get_children():
		if child is Label:
			drawer_title = child
			drawer_title.add_theme_font_size_override("font_size", 20)
	hud._drawer_toggle.text = "Close"
	hud._drawer_toggle.custom_minimum_size = Vector2(58, 36)
	outer.get_node("PersistenceControls").visible = false
	# Move raw coordinates and direct numeric placement behind one advanced control.
	var coords: Control = hud._x.get_parent().get_parent()
	var parent: Control = coords.get_parent()
	var toggle := CheckButton.new()
	toggle.text = "Advanced placement"
	toggle.focus_mode = Control.FOCUS_NONE
	parent.add_child(toggle)
	parent.move_child(toggle, coords.get_index())
	coords.visible = false
	hud._place.visible = false
	toggle.toggled.connect(func(on: bool):
		coords.visible = on
		hud._place.visible = on
		hud._fit_drawer.call_deferred())
	hud._priority.get_parent().visible = false
	hud._suggest_button.text = "Choose best crew"
	hud._assign_button.text = "Assign crew"
	hud._place_on_map.text = "Place on the map"
	for i in hud._catalog_menu.item_count:
		if str(hud._catalog_menu.get_item_metadata(i)) == "greenhouse_mk1": hud._catalog_menu.select(i)
	hud._drill_button.text = "Practice a fault"
	hud._repair_button.text = "Repair equipment"
	_build_dock()
	_build_transport()
	# The existing camp model remains authoritative; this only adds a direct action.
	hud._camp_card.add_theme_stylebox_override("panel", surface())
	var body: Control = hud._camp_text.get_parent()
	mission_title = Label.new()
	mission_title.add_theme_font_size_override("font_size", 23)
	mission_title.add_theme_color_override("font_color", INK)
	mission_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(mission_title)
	body.move_child(mission_title, 0)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 5
	progress.show_percentage = false
	progress.max_value = 6
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#304753")
	track.set_corner_radius_all(2)
	var fill := track.duplicate()
	fill.bg_color = TEAL
	progress.add_theme_stylebox_override("background", track)
	progress.add_theme_stylebox_override("fill", fill)
	body.add_child(progress)
	body.move_child(progress, 1)
	hud._camp_text.add_theme_font_size_override("font_size", 16)
	action = Button.new()
	action.custom_minimum_size.y = 42
	action.focus_mode = Control.FOCUS_NONE
	action.add_theme_stylebox_override("normal", button_style(TEAL))
	action.add_theme_stylebox_override("hover", button_style(TEAL.lightened(0.12)))
	action.add_theme_stylebox_override("pressed", button_style(TEAL.darkened(0.12)))
	action.add_theme_color_override("font_color", Color("#102c32"))
	action.add_theme_color_override("font_hover_color", Color("#102c32"))
	action.pressed.connect(_mission_action)
	body.add_child(action)
	body.move_child(action, 3)
	hud._storm_save.text = "Protect oxygen"
	hud._storm_keep.text = "Keep farm on"
	hud._storm_practice.text = "Try a dust storm"
	radiation_choices = HBoxContainer.new()
	radiation_choices.add_theme_constant_override("separation", 8)
	body.add_child(radiation_choices)
	for choice in [["Shelter crew", true], ["Keep working", false]]:
		var button := Button.new()
		button.text = choice[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_radiation_response.bind(choice[1]))
		radiation_choices.add_child(button)
	radiation_choices.visible = false
	layout()

func _build_dock() -> void:
	dock = hud._panel(hud)
	dock.name = "ActionDock"
	var row: HBoxContainer = hud._row(dock, 8)
	for entry in [["Build", "build", "Build"], ["Crew", "crew", "Crew"], ["Jobs", "jobs", "Jobs"], ["Explore", "eva", "EVA"], ["Colony", "systems", "Systems"], ["Goals", "guide", "Guide"]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size = Vector2(100, 48)
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = {"Build":"Place and inspect camp equipment", "Crew":"Your astronauts, skills and needs", "Jobs":"Assign crew and track their work", "Explore":"Plan expeditions and recover supplies", "Colony":"Life support, power and alerts", "Goals":"Your mission and next steps"}[entry[0]]
		button.pressed.connect(_navigate.bind(entry[2]))
		row.add_child(button)
		nav[entry[2]] = button

func _build_transport() -> void:
	transport = hud._panel(hud)
	transport.name = "TimeControls"
	var body: VBoxContainer = hud._column(transport, 5)
	hud._clock.reparent(body)
	hud._clock.add_theme_font_size_override("font_size", 15)
	var time: Control = hud._speed_buttons[0].get_parent()
	time.reparent(body)
	time.add_theme_constant_override("separation", 10)
	for key in hud._speed_buttons:
		var button: Button = hud._speed_buttons[key]
		button.custom_minimum_size = Vector2(54, 38)
		button.text = ""
		for child in button.get_children(): child.queue_free()
		var icon := PlaybackIcon.new()
		icon.triangles = {0:0, 1:1, 5:2, 20:3}[key]
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		playback_icons[key] = icon

func _navigate(title: String) -> void:
	if title == "Crew":
		hud._crew_card.visible = not hud._crew_card.visible
		if hud._crew_card.visible:
			hud._drawer_open = false
			hud._apply_layout()
		layout()
		refresh(true)
		return
	hud._crew_card.visible = false
	if title == "Build" and hud._inspect_section.visible:
		hud._inspect_section.visible = false
		hud._placement_section.visible = true
		hud._open_tab("Build")
		hud._fit_drawer.call_deferred()
		refresh(true)
		return
	if hud._drawer_open and hud._tabs.get_current_tab_control().name == title:
		hud._toggle_drawer()
	else:
		hud._open_tab(title)
	layout()
	refresh(true)

func layout() -> void:
	if dock == null: return
	var w: float = hud.size.x
	var h: float = hud.size.y
	dock.position = Vector2(maxf(330, (w - 700) * 0.5), h - 84)
	dock.size = Vector2(700, 68)
	transport.position = Vector2(16, h - 98)
	transport.size = Vector2(292, 82)
	hud._top.offset_left = 16
	hud._top.offset_top = 12
	hud._top.offset_right = -16
	hud._top.offset_bottom = 64
	hud._drawer.offset_top = 78
	hud._drawer.offset_right = -16
	hud._drawer.offset_left = -376
	hud._drawer.visible = hud._drawer_open
	hud._drawer.get_child(0).get_node("PersistenceControls").visible = false
	hud._drawer_toggle.text = "Close"
	hud._drawer.offset_bottom = minf(h - 112, maxf(340, hud._drawer.offset_bottom))
	hud._camp_card.anchor_left = 0
	hud._camp_card.anchor_right = 0
	hud._camp_card.offset_left = 16
	hud._camp_card.offset_right = 344
	hud._camp_card.offset_top = 78
	hud._camp_card.offset_bottom = 78
	hud._camp_card.custom_minimum_size = Vector2(328, 0)
	hud._crew_card.offset_left = w - 376
	hud._crew_card.offset_right = w - 16
	hud._crew_card.offset_top = 78
	hud._crew_card.offset_bottom = minf(h - 116, 760)
	if hud._tour_enabled and hud._tour.active:
		hud._crew_card.offset_left = 16
		hud._crew_card.offset_right = 272
	# A few legible resources stay visible. Full accounting is one Colony click away.
	for name in ["co2", "battery"]:
		hud._chips[name].label.get_parent().visible = false
	hud._chips.food.label.get_parent().visible = true
	hud._toast.offset_left = 360
	hud._toast.offset_right = minf(w - 390, 1040)
	hud._toast.offset_bottom = -102
	hud._toast.offset_top = -144
	if drawer_title != null:
		var label: String = str(hud._tabs.get_current_tab_control().name)
		drawer_title.text = {"Jobs":"Crew assignments", "Build":"Build your camp", "EVA":"Explore Mars", "Systems":"Colony status", "Guide":"Mission goals"}.get(label, label)
		if label == "Build" and hud._inspect_section.visible: drawer_title.text = "Equipment details"
	hud.layout_changed.emit(0.0, 376.0 if hud._drawer_open or hud._crew_card.visible else 0.0)

func refresh(force: bool = false) -> void:
	if hud._state.is_empty() or mission_title == null: return
	var current_profile: String = str(hud._state.campaign_id)
	if _profile != current_profile:
		_profile = current_profile
		var legacy_tutorial: bool = hud._tour_enabled and hud._tour.active
		hud._drawer_open = legacy_tutorial
		hud._crew_card.visible = legacy_tutorial
		hud._tabs.tabs_visible = legacy_tutorial
		hud._crew.visible = legacy_tutorial
		roster.visible = not legacy_tutorial
		hud._apply_layout()
	if not _catalog_initialized and hud._catalog_menu.item_count > 0:
		for i in hud._catalog_menu.item_count:
			if str(hud._catalog_menu.get_item_metadata(i)) == "greenhouse_mk1": hud._catalog_menu.select(i)
		_catalog_initialized = true
		hud._preview_build()
	var revision: int = int(hud._state.revision)
	var placing: bool = hud._world_placement.active
	if not force and revision == _last_revision and hud._tabs.current_tab == _last_tab and placing == _last_placing: return
	_last_revision = revision
	_last_tab = hud._tabs.current_tab
	_last_placing = placing
	hud._hud_title.text = "TRAINING COLONY" if current_profile.begins_with("fixture_") else "MARS OUTPOST"
	if hud._tour_enabled and hud._tour.active and not current_profile.begins_with("fixture_"): hud._hud_title.text = "REFERENCE COLONY"
	if hud._state.alerts.is_empty():
		hud._alerts.text = "No active alerts"
		hud._alerts.add_theme_color_override("font_color", INK)
		hud._alert_chip.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		var count: int = hud._state.alerts.size()
		hud._alerts.text = "%d alert%s" % [count, "" if count == 1 else "s"]
		hud._alerts.add_theme_color_override("font_color", Color("#f3bb69"))
		hud._alert_icon.set_color(Color("#f3bb69"))
		hud._alert_chip.add_theme_stylebox_override("panel", button_style(Color("#43382c")))
	var seconds: int = int(hud._state.clock.elapsed_s)
	hud._clock.text = "Day %d  ·  %02d:%02d  ·  %s" % [1 + seconds / 86400, (seconds % 86400) / 3600, (seconds % 3600) / 60, "Paused" if int(hud._state.clock.time_scale) == 0 else "Playing"]
	for key in playback_icons:
		playback_icons[key].ink = Color("#102c32") if int(hud._state.clock.time_scale) == key else INK
		playback_icons[key].queue_redraw()
	for name in nav:
		nav[name].set_pressed_no_signal(hud._crew_card.visible if name == "Crew" else (hud._drawer_open and str(hud._tabs.get_current_tab_control().name) == name))
	var objective: Dictionary = hud.camp_objective()
	var step: int = int(objective.step)
	progress.value = step - 1 if step < 6 else 6
	mission_title.text = {1:"Build your first farm", 2:"Choose a builder", 3:"Building your farm", 4:"Assign a botanist", 5:"Equipment needs repair", 6:"Your camp is established"}[step]
	action.text = {1:"Place your farm", 2:"Assign the best builder", 3:"Let the crew build", 4:"Assign a botanist", 5:"Repair the equipment", 6:"See camp goals"}[step]
	var short: String = {1:"Fresh food needs water and power.\n8 alloy + 3 electronics", 2:"Engineers build faster. We can choose an available astronaut for you.", 3:"Unpause and watch your crew work.", 4:"A botanist turns tending into a harvest.", 5:"Incident: choose an engineer for an easier hands-on repair.", 6:"Level 1 reached. Watch your reserves and the weather."}[step]
	var storm: Dictionary = hud.storm_state()
	var radiation: Dictionary = hud._simulation.get_radiation_state() if hud._simulation != null and hud._simulation.has_method("get_radiation_state") else {"status":"idle"}
	radiation_choices.visible = radiation.status in ["warning", "active"]
	action.visible = true
	progress.visible = true
	mission_title.add_theme_color_override("font_color", INK)
	if storm.status in ["forecast", "active"]:
		mission_title.text = "Dust storm approaching" if storm.status == "forecast" else "Ride out the storm"
		var now: int = int(hud._state.clock.tick_index)
		var left: int = maxi(0, int(storm.arrival_tick if storm.status == "forecast" else storm.end_tick) - now)
		short = ("Arrives in %d min.\n" if storm.status == "forecast" else "%d min remaining.\n") % ceili(left / 60.0)
		short += "Solar drops to 25%. Pause farming to save power, or use batteries to keep growing food."
		action.visible = false
		progress.visible = false
		mission_title.add_theme_color_override("font_color", Color("#f3bb69"))
		hud._storm_save.disabled = false
		hud._storm_keep.disabled = false
		hud._storm_save.toggle_mode = true
		hud._storm_keep.toggle_mode = true
		hud._storm_save.set_pressed_no_signal(storm.response == "save_power")
		hud._storm_keep.set_pressed_no_signal(storm.response == "keep_farm")
	elif bool(hud.camp_progress().get("emergency", false)):
		short = str(objective.text)
		action.text = "Check life support"
	elif placing:
		mission_title.text = "Choose a spot"
		short = "Click open ground beside your camp.\nR rotates · Esc cancels"
		action.text = "Cancel placement"
	if radiation.status in ["warning", "active"]:
		mission_title.text = "Solar radiation alert" if radiation.status == "warning" else "Solar radiation storm"
		short = "Particles from a solar eruption reduce health. Shelter cuts exposure by 90%, but crew work pauses.\n"
		short += "Crew are sheltering." if radiation.sheltering else "Crew are currently unprotected."
		short += "\nGame risk model; not a medical dose."
		action.visible = false
		progress.visible = false
		mission_title.add_theme_color_override("font_color", Color("#f3bb69"))
	hud._camp_text.text = short
	hud._camp_text.tooltip_text = "Step %d of 6\n%s" % [step, str(objective.text)]
	var resources: Dictionary = hud._state.resources
	hud._chips.oxygen.label.text = "Oxygen  %.0f kg" % float(resources.oxygen_kg.amount)
	hud._chips.water.label.text = "Water  %.0f kg" % float(resources.potable_water_kg.amount)
	var charge := roundi(100.0 * float(hud._state.power.battery_stored_kwh) / maxf(0.001, float(hud._state.power.battery_capacity_kwh)))
	hud._chips.power.label.text = "Power  %.1f kW · %d%% battery" % [float(hud._state.power.generated_kw), charge]
	hud._chips.food.label.text = "Food  %.0f kcal" % float(resources.food_kcal.amount)
	var task: Dictionary = hud._state.tasks.get(hud._selected(hud._tasks), {})
	if not task.is_empty():
		var percent: int = roundi(100.0 * float(task.completed_work_s) / maxf(1.0, float(task.required_work_s)))
		hud._task_text.text = "%s · %d%% complete\n%d of %d crew assigned" % [str(task.status).capitalize(), percent, task.assigned_crew_ids.size(), task.crew_required]
		if task.blocked_code != null: hud._task_text.text += "\n" + hud._explain(task.blocked_code)
	for i in hud._crew.item_count:
		var id: String = str(hud._crew.get_item_metadata(i))
		var member: Dictionary = hud._state.crew[id]
		if hud._crew_card.visible:
			if not portraits.has(id): portraits[id] = _portrait(member)
			hud._crew.set_item_icon(i, portraits[id])
		var ranked: Array = member.skills.keys()
		ranked.sort_custom(func(a, b): return member.skills[a] > member.skills[b])
		var role: String = CrewLooks.ROLE_LABELS.get(str(ranked[0]), str(ranked[0]).capitalize()) if not ranked.is_empty() else "Crew"
		var activity: String = "Ready" if member.status == "idle" else str(member.status).capitalize()
		if radiation.status in ["warning", "active"] and radiation.get("sheltering", false): activity = "Sheltering"
		hud._crew.set_item_text(i, "%s\n%s · %s" % [hud._crew_name(member.display_name), role, activity])
		if hud._crew_card.visible and roster.visible:
			if not crew_rows.has(id):
				var row := CrewRow.new()
				roster.add_child(row)
				row.pressed.connect(_select_crew.bind(id))
				crew_rows[id] = row
			crew_rows[id].display(hud._crew_name(member.display_name), "%s · %s" % [role, activity], portraits[id], id in hud._selected_crew())
	layout()

func _radiation_response(shelter: bool) -> void:
	hud._send("set_radiation_shelter", {"enabled": shelter})

func _select_crew(id: String) -> void:
	var multi := Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL)
	var selected: Array = hud._selected_crew()
	if not multi: hud._crew.deselect_all()
	for i in hud._crew.item_count:
		if str(hud._crew.get_item_metadata(i)) == id:
			if multi and id in selected: hud._crew.deselect(i)
			else: hud._crew.select(i, false)
	hud.crew_selected.emit(id)
	hud._refresh_selection()
	refresh(true)

func _portrait(member: Dictionary) -> Texture2D:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 96)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	hud.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#294552")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -30, 0)
	light.light_energy = 1.2
	viewport.add_child(light)
	var figure := Figure.new()
	figure.manual_time = true
	viewport.add_child(figure)
	figure.apply_look(CrewLooks.look_for(str(member.definition_id), str(member.display_name)))
	var camera := Camera3D.new()
	camera.fov = 32
	viewport.add_child(camera)
	var head_y: float = figure.figure_height() - 0.30
	camera.look_at_from_position(Vector3(0, head_y + 0.02, 1.25), Vector3(0, head_y, 0))
	return viewport.get_texture()

func _mission_action() -> void:
	if hud._world_placement.active:
		hud.placement_cancel_requested.emit()
		return
	var storm: Dictionary = hud.storm_state()
	if storm.status in ["forecast", "active"] or bool(hud.camp_progress().get("emergency", false)):
		hud._open_tab("Systems")
		return
	var step: int = int(hud.camp_objective().step)
	if step == 1:
		for i in hud._catalog_menu.item_count:
			if str(hud._catalog_menu.get_item_metadata(i)) == "greenhouse_mk1": hud._catalog_menu.select(i)
		hud.placement_requested.emit("greenhouse_mk1", 0)
	elif step in [2, 4]:
		var kind := "construct" if step == 2 else "farm"
		for i in hud._tasks.item_count:
			var id: String = str(hud._tasks.get_item_metadata(i))
			var task: Dictionary = hud._state.tasks[id]
			var building: Dictionary = hud._state.buildings.get(task.target_id, {})
			if task.kind == kind and "greenhouse" in str(building.get("definition_id", "")) and task.status not in ["completed", "cancelled", "failed"]:
				hud._tasks.select(i)
				hud._suggest()
				hud._assign()
				hud._time(1)
				break
	elif step == 3: hud._time(1)
	elif step == 5:
		for id in hud.repair_state().faults:
			if hud.repair_state().faults[id].status == "open":
				hud.select_building(id)
				hud._start_repair()
				break
	else: hud._open_tab("Guide")
