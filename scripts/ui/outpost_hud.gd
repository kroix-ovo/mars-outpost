extends Control
## Mission control overlay. Read-only snapshot view: controls send v2 commands through the
## supplied facade and never write simulation state.
##
## Layout: a compact resource/status strip along the top, a floating crew roster on the left,
## a collapsible contextual drawer (Jobs / Build / EVA / Systems / Guide) on the right and a
## status toast at the bottom left. Empty space passes mouse input to the world.

const FirstShift = preload("res://scripts/ui/first_shift.gd")
const SaveSlot = preload("res://scripts/ui/outpost_save_slot.gd")
const Icon = preload("res://scripts/ui/hud_icon.gd")
const TERMINAL := ["completed", "cancelled", "failed"]
const INK := Color("#e4dfd5")
const DIM := Color("#9a958c")
const AMBER := Color("#e8962a")
const CYAN := Color("#5cc8e8")
const DANGER := Color("#ec6a52")
const OK_GREEN := Color("#7fcf7a")
const PANEL := Color(0.075, 0.085, 0.10, 0.92)
const DRAWER_WIDTH := 384.0
const CREW_WIDTH := 252.0
const TOP_HEIGHT := 46.0

signal reference_requested
signal crew_selected(crew_id: String)
signal placement_preview(request: Dictionary, result: Dictionary)
## Emitted when the visible world area changes: pixels covered on the left and right.
signal layout_changed(left_px: float, right_px: float)
signal crew_selection_changed(crew_ids: Array)
## Asks the world to show the placement ghost for this definition.
signal placement_requested(definition_id: String, rotation_quarters: int)

var _simulation: RefCounted
var _adapter: RefCounted
var _world: RefCounted
var _catalog: Dictionary = {}
var _save_path := "user://outpost_quick_save.json"
var _state: Dictionary = {}
var _session := ""
var _seq := 0
var _pending: Dictionary = {}
var _mission := FirstShift.new()
var _mission_reset := true
var _mission_title: Label
var _mission_text: Label
var _mission_action: Button
var _stale := false
var _alert_ids: Array = []
var _hud_title: Label
var _clock: Label
var _vitals: Label
var _alerts: Label
var _status: Label
var _tutorial_text: Label
var _crew: ItemList
var _crew_text: Label
var _tasks: OptionButton
var _task_text: Label
var _priority: SpinBox
var _resources: Label
var _oxygen_info: Label
var _buildings: OptionButton
var _building_text: Label
var _toggle_building: Button
var _catalog_menu: OptionButton
var _x: SpinBox
var _z: SpinBox
var _rotation: SpinBox
var _build_preview: Label
var _place: Button
var _place_on_map: Button
var _sites: OptionButton
var _trips: OptionButton
var _work: SpinBox
var _oxygen: SpinBox
var _battery: SpinBox
var _eva_forecast: Label
var _trip_text: Label
var _launch: Button
var _recall: Button
var _audio: AudioStreamPlayer
var _mute: CheckButton
var _tabs: TabContainer
var _save_button: Button
var _load_button: Button
var _speed_buttons: Dictionary = {}
var _chips: Dictionary = {}  # resource key -> {label, icon}
var _alert_chip: PanelContainer
var _alert_icon: Control
var _top: PanelContainer
var _crew_body: VBoxContainer
var _crew_card: PanelContainer
var _drawer: PanelContainer
var _drawer_body: VBoxContainer
var _drawer_toggle: Button
var _toast: PanelContainer
var _detail_toggle: Button
var _alert_list: Label
var _crew_hint: Label
var _drawer_open := true

func _refresh_capabilities() -> void:
	var persistence := true
	if _simulation != null and _simulation.has_method("get_capabilities"):
		persistence = _simulation.get_capabilities().get("persistence", false)
	for button in [_save_button, _load_button]:
		if button != null:
			button.disabled = not persistence
			button.tooltip_text = "" if persistence else "Campaign saves will be available in the persistence phase."

func bind(simulation: RefCounted, crew_adapter: RefCounted, world_service: RefCounted,
		building_catalog: Dictionary = {}, save_path: String = "user://outpost_quick_save.json") -> void:
	if _simulation != null:
		_simulation.disconnect("state_changed", _on_snapshot)
		_simulation.disconnect("game_event", _on_event)
	_simulation = simulation
	_adapter = crew_adapter
	_world = world_service
	_catalog = building_catalog.duplicate(true)
	_save_path = save_path
	_state = {}
	_pending.clear()
	_mission_reset = true
	_alert_ids.clear()
	_reset_session()
	if _simulation == null:
		return
	_simulation.connect("state_changed", _on_snapshot)
	_simulation.connect("game_event", _on_event)
	if is_node_ready():
		_on_snapshot(_simulation.get_snapshot())
		_refresh_capabilities()
		_open_tab("Guide")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_build_top_bar()
	_build_crew_card()
	_build_drawer()
	_build_toast()
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	resized.connect(_apply_layout)
	_apply_layout()
	if _simulation != null:
		_on_snapshot(_simulation.get_snapshot())
	else:
		_refresh_guide()
	_refresh_capabilities()

# ---------------------------------------------------------------- layout

func _build_top_bar() -> void:
	_top = _panel(self)
	_top.name = "StatusStrip"
	_top.anchor_right = 1.0
	_top.offset_left = 8
	_top.offset_top = 8
	_top.offset_right = -8
	_top.custom_minimum_size.y = TOP_HEIGHT
	var row := _row(_top, 10)
	_hud_title = _label(row, "MARS OUTPOST", 13)
	_hud_title.add_theme_color_override("font_color", AMBER)
	_hud_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hud_title.tooltip_text = "F2 restarts synthetic training · F3 restarts the reference colony"
	_hud_title.mouse_filter = Control.MOUSE_FILTER_PASS
	_separator(row)
	var time := _row(row, 2)
	for entry in [[0, "pause", "Pause (Space)"], [1, "1×", "Normal speed"], [5, "5×", "Fast"], [20, "20×", "Fastest"]]:
		var button: Button
		if entry[1] == "pause":
			button = _button(time, "", func(): _time(0))
			var pause_icon := Icon.make("pause", INK, 14)
			button.add_child(pause_icon)
			pause_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
			button.custom_minimum_size = Vector2(34, 28)
		else:
			button = _button(time, entry[1], _time.bind(entry[0]))
			button.custom_minimum_size = Vector2(38, 28)
		button.tooltip_text = entry[2]
		button.toggle_mode = true
		_speed_buttons[entry[0]] = button
	_clock = _label(row, "", 13)
	_clock.autowrap_mode = TextServer.AUTOWRAP_OFF
	_clock.custom_minimum_size.x = 92
	_separator(row)
	_vitals = _chip(row, "oxygen", "O₂", CYAN)
	_chip(row, "water", "water", Color("#6fa9e0"))
	_chip(row, "power", "power", AMBER)
	_chip(row, "battery", "battery", OK_GREEN)
	_chip(row, "co2", "co2", Color("#b9b3a8"))
	_chip(row, "food", "food", Color("#a7c76a"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_alert_chip = PanelContainer.new()
	_alert_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	_alert_chip.add_theme_stylebox_override("panel", _box(Color(0.2, 0.12, 0.08, 0.0), 4, 6, 2))
	row.add_child(_alert_chip)
	var alert_row := _row(_alert_chip, 6)
	_alert_icon = Icon.make("alert", DIM, 15)
	alert_row.add_child(_alert_icon)
	_alerts = _label(alert_row, "No active alerts", 13)
	_alerts.autowrap_mode = TextServer.AUTOWRAP_OFF
	_alerts.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_alerts.custom_minimum_size.x = 120
	_alert_chip.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_open_tab("Systems"))

func _build_crew_card() -> void:
	_crew_card = _panel(self)
	_crew_card.name = "CrewCard"
	_crew_card.offset_left = 8
	_crew_card.offset_top = 64
	_crew_card.offset_right = 8 + CREW_WIDTH
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_crew_card.add_child(scroll)
	var body := _column(scroll, 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crew_body = body
	var head := _row(body, 6)
	head.add_child(Icon.make("crew", AMBER, 16))
	var crew_title := _label(head, "CREW", 13)
	crew_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	crew_title.add_theme_color_override("font_color", AMBER)
	_crew_hint = _label(body, "Ctrl/Shift: select several", 16)
	_crew_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_crew_hint.add_theme_color_override("font_color", DIM)
	_crew_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crew_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_crew = ItemList.new()
	_crew.select_mode = ItemList.SELECT_MULTI
	_crew.auto_height = true
	_crew.focus_mode = Control.FOCUS_NONE
	_crew.custom_minimum_size = Vector2(CREW_WIDTH - 20, 40)
	_crew.tooltip_text = "Select astronauts for jobs and EVA. Ctrl / Command or Shift selects several."
	body.add_child(_crew)
	_crew.multi_selected.connect(func(index: int, selected: bool):
		if selected:
			crew_selected.emit(str(_crew.get_item_metadata(index)))
		_refresh_selection())
	_crew_text = _label(body, "", 12)
	_crew_text.add_theme_color_override("font_color", DIM)
	var rule := HSeparator.new()
	body.add_child(rule)
	_mission_title = _label(body, "FIRST SHIFT", 16)
	_mission_title.add_theme_color_override("font_color", AMBER)
	_mission_text = _label(body, "", 16)
	_mission_action = _button(body, "Open EVA", _mission_next)

func _build_drawer() -> void:
	_drawer = _panel(self)
	_drawer.name = "Drawer"
	_drawer.anchor_left = 1.0
	_drawer.anchor_right = 1.0
	_drawer.offset_top = 64
	_drawer.offset_right = -8
	var outer := _column(_drawer, 6)
	var head := _row(outer, 4)
	_drawer_toggle = _button(head, "»", _toggle_drawer)
	_drawer_toggle.tooltip_text = "Hide or show mission control"
	_drawer_toggle.custom_minimum_size = Vector2(30, 26)
	var drawer_title := _label(head, "MISSION CONTROL", 13)
	drawer_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	drawer_title.add_theme_color_override("font_color", AMBER)
	var tools := _row(outer, 6)
	tools.name = "PersistenceControls"
	_save_button = _button(tools, "Save", func(): _save_load.call_deferred(false))
	_load_button = _button(tools, "Load", func(): _save_load.call_deferred(true))
	_mute = CheckButton.new()
	_mute.focus_mode = Control.FOCUS_NONE
	_mute.tooltip_text = "Mute interface sounds"
	_mute.add_theme_font_size_override("font_size", 16)
	_mute.text = "Mute"
	tools.add_child(_mute)
	_drawer_body = _column(outer, 6)
	_drawer_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.tab_changed.connect(func(_i: int):
		if _tabs.get_tab_title(_tabs.current_tab) == "Systems" and not _state.is_empty():
			_mission.done.systems = true
			_refresh_guide()
		_fit_drawer.call_deferred())
	_drawer_body.add_child(_tabs)

	var jobs := _page("Jobs")
	_section(jobs, "Job")
	_tasks = _option(jobs)
	_tasks.item_selected.connect(func(_i: int): _refresh_selection())
	_task_text = _label(jobs, "", 13)
	_priority = _number(jobs, "Priority (higher first)", 0, 100, 1, 50)
	var job_actions := _row(jobs, 6)
	var suggest := _button(job_actions, "Suggest crew", _suggest)
	suggest.tooltip_text = "Select the recommended available astronauts"
	var assign := _button(job_actions, "Assign selected", _assign)
	assign.tooltip_text = "Assign the astronauts selected in the crew roster"
	var cancel := _button(jobs, "Cancel job", func():
		var id := _selected(_tasks)
		if not id.is_empty():
			_send("cancel_task", {"task_id": id}))
	cancel.tooltip_text = "Cancelling unfinished construction refunds its prepaid materials"
	_hint(jobs, "Pick astronauts in the crew roster, then assign them. Repairs restore damaged modules; construction finishes placed modules.")

	var build := _page("Build")
	_section(build, "Selected module")
	_buildings = _option(build)
	_buildings.item_selected.connect(func(_i: int): _refresh_selection())
	_building_text = _label(build, "", 13)
	_toggle_building = _button(build, "Toggle module", _toggle)
	_section(build, "Place a module")
	_catalog_menu = _option(build)
	_catalog_menu.item_selected.connect(func(_i: int): _preview_build())
	_place_on_map = _button(build, "Choose a cell on the map", func():
		placement_requested.emit(_selected(_catalog_menu), int(_rotation.value)))
	_place_on_map.tooltip_text = "Shows the module outline under the cursor. Click to place, R rotates, Esc cancels."
	var coords := _row(build, 6)
	_x = _number(coords, "Cell X", 0, 100000, 1, 0)
	_z = _number(coords, "Cell Z", 0, 100000, 1, 0)
	_rotation = _number(coords, "Turns", 0, 3, 1, 0)
	for field in [_x, _z, _rotation]:
		field.value_changed.connect(func(_v: float): _preview_build())
	_build_preview = _label(build, "", 13)
	_place = _button(build, "Place at these coordinates", func(): _send("place_building", _placement()))

	var eva := _page("EVA")
	_section(eva, "Plan a salvage trip")
	_hint(eva, "Uses the astronauts selected in the crew roster.")
	_sites = _option(eva)
	_sites.item_selected.connect(func(_i: int): _preview_eva())
	var supplies := _row(eva, 6)
	_work = _number(supplies, "Work s", 1, 100000, 1, 20)
	_oxygen = _number(supplies, "O₂ kg each", 0, 1000, 0.00001, 0.12)
	_battery = _number(supplies, "kWh each", 0, 1000, 0.00001, 0.006)
	for field in [_work, _oxygen, _battery]:
		field.value_changed.connect(func(_v: float): _preview_eva())
	_eva_forecast = _label(eva, "", 12)
	_launch = _button(eva, "Launch expedition", func(): _send("start_eva", _eva_request()))
	_section(eva, "Expeditions")
	_trips = _option(eva)
	_trips.item_selected.connect(func(_i: int): _refresh_selection())
	_trip_text = _label(eva, "", 12)
	_recall = _button(eva, "Recall expedition", func():
		_send("recall_eva", {"expedition_id": _selected(_trips)}))

	var systems := _page("Systems")
	_section(systems, "Alerts")
	_alert_list = _label(systems, "No active alerts", 13)
	_section(systems, "Life support")
	_oxygen_info = _label(systems, "", 13)
	_detail_toggle = _button(systems, "Show detailed accounting", func():
		_resources.visible = not _resources.visible
		_detail_toggle.text = "Hide detailed accounting" if _resources.visible else "Show detailed accounting")
	_resources = _label(systems, "", 12)
	_resources.visible = false

	var onboarding := _page("Guide")
	_tutorial_text = _label(onboarding, "", 13)
	_hint(onboarding, "Pause to plan; commands also resolve while paused. Resume at 1×, 5× or 20×. F2 starts training with synthetic values; F3 starts the reference life-support scenario. F1 shows diagnostics. Campaign saves and agriculture are pending.")
	_hint(onboarding, "Camera: WASD or middle-drag pans, right-drag or Q/E orbits, wheel zooms, Home recentres. Click modules, sites or astronauts to inspect them.")

func _build_toast() -> void:
	_toast = _panel(self)
	_toast.name = "StatusToast"
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = 8 + CREW_WIDTH + 12
	_toast.offset_top = -44
	_toast.offset_bottom = -8
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status = _label(_toast, "Ready", 13)
	_status.add_theme_color_override("font_color", Color("#abd5fa"))
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF

func _apply_layout() -> void:
	if _drawer == null:
		return
	var width := size.x if size.x > 0 else 1600.0
	# Keep the essentials readable at 720p; full accounting remains in Systems.
	for key in ["co2", "food"]:
		_chips[key].label.get_parent().visible = width >= 1450.0
	var drawer_width := DRAWER_WIDTH if width >= 1400 else 352.0
	_drawer.offset_left = -8 - (drawer_width if _drawer_open else 46.0)
	_drawer_body.visible = _drawer_open
	_drawer.get_child(0).get_node("PersistenceControls").visible = _drawer_open
	for child in _drawer_toggle.get_parent().get_children():
		if child != _drawer_toggle:
			child.visible = _drawer_open
	_drawer_toggle.text = "»" if _drawer_open else "«"
	_crew_card.offset_top = 8 + TOP_HEIGHT + 8
	_drawer.offset_top = 8 + TOP_HEIGHT + 8
	_fit_crew_card.call_deferred()
	var right_edge := width - 8 - (drawer_width if _drawer_open else 46.0) - 12
	_toast.offset_right = minf(right_edge, _toast.offset_left + 620.0)
	_fit_drawer.call_deferred()
	layout_changed.emit(8.0 + CREW_WIDTH, 8.0 + (drawer_width if _drawer_open else 46.0))

func _fit_crew_card() -> void:
	if _crew_body == null or not is_inside_tree():
		return
	var available := maxf(80.0, size.y - _crew_card.offset_top - 8.0)
	var height := minf(available, _crew_body.get_combined_minimum_size().y + 24.0)
	_crew_card.offset_bottom = _crew_card.offset_top + height

func _fit_drawer() -> void:
	## The drawer is only as tall as the open page needs, so the world stays visible below it.
	if _drawer == null or not is_inside_tree():
		return
	var available := size.y - _drawer.offset_top - 8.0
	var want := 52.0
	if _drawer_open:
		var page := _tabs.get_current_tab_control()
		var inner: Control = page.get_child(0) if page != null and page.get_child_count() > 0 else null
		want = 128.0 + (inner.get_combined_minimum_size().y if inner != null else 0.0)
	_drawer.offset_bottom = _drawer.offset_top + clampf(want, 52.0, maxf(available, 52.0))

func refresh_layout() -> void:
	_apply_layout()

func _toggle_drawer() -> void:
	_drawer_open = not _drawer_open
	_apply_layout()

func _open_tab(title: String) -> void:
	if not _drawer_open:
		_toggle_drawer()
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_title(i) == title:
			_tabs.current_tab = i
			return

# ---------------------------------------------------------------- public hooks

func select_crew(id: String) -> void:
	if _crew == null:
		return
	for index in range(_crew.item_count):
		if _crew.get_item_metadata(index) == id:
			_crew.select(index)
			_refresh_selection()
			return

func select_building(id: String) -> void:
	## World selection of a module: inspect it in the Build drawer.
	if _buildings == null or id.is_empty():
		return
	for i in _buildings.item_count:
		if _buildings.get_item_metadata(i) == id:
			_buildings.select(i)
			_open_tab("Build")
			_refresh_selection()
			return

func select_site(id: String) -> void:
	## World selection of a salvage site: plan a trip to it.
	if _sites == null or id.is_empty():
		return
	for i in _sites.item_count:
		if _sites.get_item_metadata(i) == id:
			_sites.select(i)
			_open_tab("EVA")
			_preview_eva()
			return

func set_placement_cell(cell: Vector2i) -> void:
	if _x != null:
		_x.set_value_no_signal(cell.x)
		_z.set_value_no_signal(cell.y)
		_preview_build()

func set_placement_rotation(quarters: int) -> void:
	if _rotation != null and int(_rotation.value) != quarters:
		_rotation.set_value_no_signal(quarters)
		_preview_build()

func selected_building_id() -> String:
	return "" if _buildings == null else _selected(_buildings)

# ---------------------------------------------------------------- snapshot binding

func _on_snapshot(snapshot: Dictionary) -> void:
	if not is_node_ready() or not snapshot.has("campaign_id"):
		return
	var tick: int = snapshot.clock.tick_index
	if _state.is_empty() or snapshot.campaign_id != _state.campaign_id or snapshot.revision < _state.revision:
		_stale = false
		if not _state.is_empty():
			_pending.clear()
			_mission_reset = true
			_reset_session()
	elif tick != int(_state.clock.tick_index):
		_stale = false
	elif snapshot.buildings != _state.buildings or snapshot.expeditions != _state.expeditions \
			or snapshot.tasks != _state.tasks:
		_stale = true
	_state = snapshot
	if _mission_reset:
		_mission.reset(snapshot)
		_mission_reset = false
	_mission.observe(snapshot)
	if _simulation != null and _simulation.has_method("get_capabilities"):
		_hud_title.text = "TRAINING · SYNTHETIC" if snapshot.campaign_id.begins_with("fixture_") else "REFERENCE COLONY"
	var scale_value: int = int(snapshot.clock.time_scale)
	_clock.text = "T+ %s  ·  %s" % [_duration(tick), "Paused" if scale_value == 0 else "%d×" % scale_value]
	for key in _speed_buttons:
		_speed_buttons[key].set_pressed_no_signal(key == scale_value)
	_refresh_roster()
	_fill_options(_tasks, _task_options())
	_fill_options(_buildings, _building_options(snapshot.buildings))
	_fill_options(_catalog_menu, _catalog_options())
	_fill_options(_sites, _labels(snapshot.sites))
	_fill_options(_trips, _labels(snapshot.expeditions))
	_refresh_life_support()
	_refresh_selection()
	_refresh_guide()
	_preview_build()
	_fit_drawer.call_deferred()

func _duration(seconds: int) -> String:
	if seconds < 120:
		return "%d s" % seconds
	if seconds < 7200:
		return "%d min %02d s" % [seconds / 60, seconds % 60]
	return "%d h %02d min" % [seconds / 3600, (seconds / 60) % 60]

func _quick_resource(id: String, title: String) -> String:
	var resource: Dictionary = _state.resources.get(id, {})
	return "%s %.2f %s" % [title, resource.amount, resource.unit] if not resource.is_empty() else title + " —"

func _refresh_chips() -> void:
	_vitals.text = _quick_resource("oxygen_kg", "O₂")
	_set_chip("water", _short_resource("potable_water_kg", "Water"), "potable_water_kg")
	var power: Dictionary = _state.get("power", {})
	var generated := float(power.get("generated_kw", 0.0))
	var requested := float(power.get("requested_kw", 0.0))
	var served := float(power.get("served_kw", 0.0))
	_chips.power.label.text = "%.1f kW" % generated
	_chips.power.label.tooltip_text = "Power: %.2f kW generated · %.2f / %.2f kW served to equipment" % [generated, served, requested]
	_chips.power.icon.set_color(DANGER if served + 1e-9 < requested else AMBER)
	var capacity := float(power.get("battery_capacity_kwh", 0.0))
	var stored := float(power.get("battery_stored_kwh", 0.0))
	_chips.battery.label.text = "%d%%" % roundi(100.0 * stored / capacity) if capacity > 0.0 else "—"
	_chips.battery.label.tooltip_text = "Battery: %.3f / %.3f kWh stored" % [stored, capacity]
	_chips.battery.icon.set_color(OK_GREEN if capacity <= 0.0 or stored >= 0.25 * capacity else DANGER)
	_set_chip("co2", _short_resource("co2_kg", "CO₂"), "co2_kg")
	_set_chip("food", _short_resource("food_kcal", "Food"), "food_kcal")
	_vitals.tooltip_text = _resource_tooltip("oxygen_kg")

func _set_chip(key: String, text: String, resource_id: String) -> void:
	_chips[key].label.text = text
	_chips[key].label.tooltip_text = _resource_tooltip(resource_id)

func _short_resource(id: String, title: String) -> String:
	var r: Dictionary = _state.resources.get(id, {})
	if r.is_empty():
		return title + " —"
	var amount := float(r.amount)
	var number := ("%.0f" % amount) if amount >= 1000 else ("%.1f" % amount if amount >= 10 else "%.2f" % amount)
	return "%s %s %s" % [title, number, r.unit]

func _resource_tooltip(id: String) -> String:
	var r: Dictionary = _state.get("resources", {}).get(id, {})
	if r.is_empty():
		return _resource_name(id) + ": not tracked in this scenario"
	var rate := 0.0 if absf(r.net_rate_per_s) < 1e-12 else float(r.net_rate_per_s)
	var text := "%s: %.3f %s available" % [_resource_name(id), float(r.amount) - float(r.reserved), r.unit]
	if r.capacity != null:
		text += " of %.3f capacity" % r.capacity
	text += "\nLast tick: %+.6f %s/s%s" % [rate, r.unit, " (waiting for next tick)" if _stale else ""]
	if r.forecast_empty_s != null and id != "co2_kg":
		text += "\nEmpty in about %s at this rate" % _duration(int(r.forecast_empty_s))
	return text

func _refresh_roster() -> void:
	var selected := _selected_crew()
	var ids := _keys(_state.crew)
	if _crew.item_count != ids.size():
		_crew.clear()
		for id in ids:
			var i := _crew.add_item("")
			_crew.set_item_metadata(i, id)
	for i in range(ids.size()):
		var id: String = ids[i]
		var member: Dictionary = _state.crew[id]
		_crew.set_item_metadata(i, id)
		_crew.set_item_text(i, "%s  ·  %s" % [member.display_name, member.status.capitalize()])
		_crew.set_item_custom_fg_color(i, INK if member.status == "idle" else (DANGER if member.status in ["dead", "incapacitated"] else CYAN))
		if id in selected:
			_crew.select(i, false)
		else:
			_crew.deselect(i)

func _refresh_selection() -> void:
	if _state.is_empty():
		return
	var details: Array[String] = []
	for id in _selected_crew():
		var c: Dictionary = _state.crew[id]
		var skills: Array[String] = []
		for skill in _keys(c.skills):
			skills.append("%s %d%%" % [skill.capitalize(), roundi(c.skills[skill] * 100)])
		details.append("%s: health %d%% · fatigue %d%% · stress %d%%\n%s" %
			[c.display_name, roundi(c.health * 100), roundi(c.fatigue * 100), roundi(c.stress * 100),
				"  /  ".join(skills)])
	var chosen := _selected_crew()
	if chosen.size() > 1:
		var names: Array[String] = []
		for id in chosen:
			names.append(_state.crew[id].display_name)
		details = ["%d selected: %s" % [chosen.size(), ", ".join(names)]]
	_crew_text.text = "Select an astronaut to inspect their skills." if details.is_empty() else "\n".join(details)
	_fit_crew_card.call_deferred()
	crew_selection_changed.emit(_selected_crew())
	var task: Dictionary = _state.tasks.get(_selected(_tasks), {})
	_task_text.text = "No jobs available." if task.is_empty() else "%s · %.1f / %.1f work s\n%d / %d crew assigned · priority %d%s" % [
		task.status.capitalize(), task.completed_work_s, task.required_work_s, task.assigned_crew_ids.size(),
		task.crew_required, task.priority, "" if task.blocked_code == null else "\nBlocked: " + _explain(task.blocked_code)]
	var building: Dictionary = _state.buildings.get(_selected(_buildings), {})
	_toggle_building.disabled = building.is_empty() or building.get("lifecycle") == "destroyed"
	_toggle_building.text = "Disable module" if building.get("enabled", false) else "Enable module"
	_building_text.text = "No modules to inspect." if building.is_empty() else "%s · condition %d%% · construction %d%%\n%.2f / %.2f kW served%s" % [
		building.lifecycle.capitalize(), roundi(building.condition * 100), roundi(building.construction_progress * 100),
		building.power_served_kw, building.power_requested_kw, _blockers(building)]
	var trip: Dictionary = _state.expeditions.get(_selected(_trips), {})
	var expedition_job: Dictionary = _state.tasks.get(trip.get("task_id"), {})
	_recall.disabled = trip.is_empty() or trip.get("status") in ["returning", "completed", "failed"]
	var suit_lines: Array[String] = []
	for id in _keys(trip.get("suit_stores", {})):
		var suit: Dictionary = trip.suit_stores[id]
		suit_lines.append("%s: %.5f kg O₂ · %.5f kWh" % [_state.crew[id].display_name, suit.oxygen_kg, suit.battery_kwh])
	_trip_text.text = "No expeditions yet." if trip.is_empty() else "%s · %.1f / %.1f m · work %.1f / %.1f s\nReturn margin: %s · Cargo: %s%s" % [
		trip.status.capitalize(), trip.route_progress_m, trip.route_distance_m, trip.work_completed_s,
		trip.work_required_s, "unavailable" if trip.return_margin_s == null else "%.1f s" % trip.return_margin_s,
		_amounts(trip.cargo), "" if suit_lines.is_empty() else "\n" + "\n".join(suit_lines)]
	if trip.get("status") == "stranded":
		_trip_text.text += "\nReturn route unavailable. Retry recall when the path opens."
	if trip.get("status") == "failed" and expedition_job.get("blocked_code") != null:
		_trip_text.text += "\nFailed: " + _explain(expedition_job.blocked_code)
	_preview_eva()

func _refresh_life_support() -> void:
	_refresh_chips()
	var lines: Array[String] = ["Resource rates: " + ("waiting for next tick (stale)" if _stale else "last completed tick")]
	for id in _keys(_state.resources):
		var r: Dictionary = _state.resources[id]
		var rate := 0.0 if absf(r.net_rate_per_s) < 1e-12 else float(r.net_rate_per_s)
		var stock := "%.3f %s available" % [r.amount - r.reserved, r.unit]
		if r.capacity != null:
			stock += " / %.3f total capacity" % r.capacity
		lines.append("%s: %s · %+.6f %s/s%s" % [_resource_name(id), stock, rate, r.unit,
			"" if r.forecast_empty_s == null or id == "co2_kg" else " · %.1f s to empty at this rate" % r.forecast_empty_s])
	var power: Dictionary = _state.power
	lines.append("Power: %.2f kW generated · %.2f / %.2f kW served" %
		[power.generated_kw, power.served_kw, power.requested_kw])
	_resources.text = "\n".join(lines)
	var oxygen: Array[String] = [
		"Power and potable water feed electrolysis. Recycling can replenish potable water; hydrogen needs storage. Crew consume oxygen. CO₂ is a separate hazard and needs scrubbing."
	]
	for id in _keys(_state.buildings):
		var b: Dictionary = _state.buildings[id]
		var d: Dictionary = _catalog.get(b.definition_id, {})
		var outputs: Dictionary = d.get("process", {}).get("outputs_per_s", {})
		var inputs: Dictionary = d.get("process", {}).get("inputs_per_s", {})
		if outputs.has("oxygen_kg") or outputs.has("potable_water_kg") or inputs.has("co2_kg") \
				or d.get("power_generation_kw", 0.0) > 0:
			oxygen.append("•  %s · %.0f%% operating%s" %
				[d.get("display_name", b.definition_id), b.operating_fraction * 100, _blockers(b)])
	_oxygen_info.text = "\n".join(oxygen)
	var alerts: Array[String] = []
	var ids: Array = []
	var new_warning := false
	var critical := false
	for alert in _state.alerts:
		alerts.append("%s: %s" % [alert.severity.capitalize(), alert.message])
		ids.append(alert.id)
		critical = critical or alert.severity == "critical"
		new_warning = new_warning or (alert.id not in _alert_ids and alert.severity != "info")
	_alert_ids = ids
	if alerts.is_empty():
		_alerts.text = "No active alerts"
	elif alerts.size() == 1:
		_alerts.text = alerts[0]
	else:
		_alerts.text = "%d alerts · %s" % [alerts.size(), _state.alerts[0].message]
	_alerts.tooltip_text = "\n".join(alerts)
	_alert_chip.tooltip_text = _alerts.tooltip_text
	var tone := DIM if alerts.is_empty() else (DANGER if critical else AMBER)
	_alert_icon.set_color(tone)
	_alerts.add_theme_color_override("font_color", INK if alerts.is_empty() else tone)
	_alert_chip.add_theme_stylebox_override("panel", _box(Color(tone, 0.0 if alerts.is_empty() else 0.16), 4, 6, 2))
	_alert_list.text = "No active alerts" if alerts.is_empty() else "\n".join(alerts)
	if new_warning:
		_play("warning")

func _blockers(building: Dictionary) -> String:
	var reasons: Array[String] = []
	for code in building.blocking_codes:
		reasons.append(_explain(code))
	return "" if reasons.is_empty() else "\nReasons: " + ", ".join(reasons)

func _explain(code: String) -> String:
	var arg := code.get_slice(":", 1)
	match code.get_slice(":", 0):
		"no_power": return "No power reaching this module"
		"partial_power": return "Only part of the requested power is available"
		"input_limited": return "Needs more " + _resource_name(arg)
		"output_full": return "Storage full for " + _resource_name(arg)
		"event_modifier": return "Affected by " + arg
		"unmet_needs": return "Crew needs were not met"
		"reserve_insufficient": return "Suit reserves exhausted or insufficient"
		"route_unreachable": return "No route to destination"
	return code.replace("_", " ").capitalize()

func _resource_name(id: String) -> String:
	return str({"oxygen_kg": "Oxygen", "co2_kg": "Carbon dioxide", "food_kcal": "Food",
		"energy_kwh": "Battery energy", "potable_water_kg": "Potable water",
		"wastewater_kg": "Wastewater", "raw_water_kg": "Raw water", "hydrogen_kg": "Hydrogen"}.get(id, id.capitalize()))

func _amounts(amounts: Dictionary) -> String:
	var parts: Array[String] = []
	for id in _keys(amounts):
		parts.append("%s %s" % [str(amounts[id]), _resource_name(id)])
	return "none" if parts.is_empty() else ", ".join(parts)

func _preview_build() -> void:
	var request := _placement()
	var definition: Dictionary = _catalog.get(request.definition_id, {})
	var result := {"valid": false, "reason": "Placement preview is unavailable."}
	if _world != null and _world.has_method("validate_placement") and not definition.is_empty() and not _state.is_empty():
		result = _world.validate_placement(request, _state)
	var supported := _supports(request.definition_id)
	if result.valid:
		if not supported:
			result = {"valid": false, "reason": "This module's production rules are not available yet."}
		for id in _keys(definition.get("build_cost", {})):
			var account: Dictionary = _state.resources.get(id, {})
			if account.is_empty() or float(account.amount) - float(account.reserved) < float(definition.build_cost[id]):
				result = result.duplicate()
				result.valid = false
				result.reason = "Not enough " + _resource_name(id) + "."
				break
	_build_preview.text = ("Ready to place. " if result.valid else result.reason + " ") + "Cost: " + _amounts(definition.get("build_cost", {}))
	_build_preview.add_theme_color_override("font_color", OK_GREEN if result.valid else INK)
	_place.disabled = not result.valid
	if _place_on_map != null:
		_place_on_map.disabled = definition.is_empty() or not supported
	placement_preview.emit(request, result)

func _supports(definition_id: String) -> bool:
	return _simulation == null or not _simulation.has_method("supports_building") or _simulation.supports_building(definition_id)

func _placement() -> Dictionary:
	return {"definition_id": _selected(_catalog_menu), "cell": [int(_x.value), int(_z.value)],
		"rotation_quarters": int(_rotation.value)}

func _eva_request() -> Dictionary:
	return {"site_id": _selected(_sites), "crew_ids": _selected_crew(), "work_duration_s": _work.value,
		"oxygen_kg_per_crew": _oxygen.value, "battery_kwh_per_crew": _battery.value}

func _preview_eva() -> void:
	var r := {"ok": false, "reason": "Select available crew and a salvage site."}
	if _adapter != null and not _state.is_empty() and not _selected_crew().is_empty() and not _selected(_sites).is_empty():
		r = _adapter.estimate_eva(_eva_request(), _state)
	var lines: Array[String] = ["Ready to launch" if r.ok else r.reason]
	if r.has("seconds"):
		lines.append("Per astronaut · emergency reserve %.0f%% of loaded supplies" % (r.reserve_fraction * 100))
		for phase in ["outbound", "working", "returning"]:
			var planned: Dictionary = r.phase_use[phase]
			lines.append("%s: %.0f s · %.5f kg O₂ · %.5f kWh" %
				[phase.capitalize(), r.seconds[phase], planned.oxygen_kg, planned.battery_kwh])
		lines.append("Expected at return: %.5f kg O₂ · %.5f kWh\nMinimum load: %.5f kg O₂ · %.5f kWh" %
			[r.remaining.oxygen_kg, r.remaining.battery_kwh, r.minimum.oxygen_kg, r.minimum.battery_kwh])
	_eva_forecast.text = "\n".join(lines)
	_eva_forecast.add_theme_color_override("font_color", OK_GREEN if r.ok else INK)
	_launch.disabled = not r.ok

func _assign() -> void:
	var id := _selected(_tasks)
	if id.is_empty() or _selected_crew().is_empty():
		_status.text = "Select a job and the astronauts who should work it."
		return
	_send("assign_task", {"task_id": id, "crew_ids": _selected_crew(), "priority": int(_priority.value)})

func _suggest() -> void:
	var id := _selected(_tasks)
	if id.is_empty() or _adapter == null:
		return
	var task: Dictionary = _state.tasks[id]
	var candidates: Array = _adapter.recommended_crew(task, _state)
	_crew.deselect_all()
	for i in range(mini(candidates.size(), int(task.crew_required) - task.assigned_crew_ids.size())):
		for idx in range(_crew.item_count):
			if _crew.get_item_metadata(idx) == candidates[i]:
				_crew.select(idx, false)
	_refresh_selection()

func _toggle() -> void:
	var id := _selected(_buildings)
	_send("set_building_enabled", {"building_id": id, "enabled": not _state.buildings[id].enabled})

func _time(scale_value: int) -> void:
	_send("set_time_scale", {"time_scale": scale_value})

func _send(type: String, payload: Dictionary) -> void:
	if _simulation == null:
		_status.text = "The colony controls are not connected."
		return
	_seq += 1
	var id := "%s:%06d" % [_session, _seq]
	var result: Dictionary = _simulation.submit_command({"contract_version": "2.0.0",
		"command_id": id, "type": type, "payload": payload})
	if result.accepted:
		_pending[id] = type
		_status.text = "Queued: " + _explain(type)
	else:
		_status.text = result.reason
		_play("warning")

func _on_event(event: Dictionary) -> void:
	if event.type == "command_result" and _pending.has(event.data.command_id):
		var type: String = _pending[event.data.command_id]
		_pending.erase(event.data.command_id)
		_status.text = _explain(type) + " accepted." if event.data.success else event.data.reason
		if event.data.success:
			_refresh_guide()
		_play("confirm" if event.data.success else "warning")
	elif event.type in ["building_commissioned", "eva_returned", "task_completed"]:
		_status.text = _explain(event.type)
		_play("confirm")

func _save_load(load_game: bool) -> void:
	if _simulation == null:
		return
	var result := SaveSlot.load_slot(_simulation, _save_path) if load_game else SaveSlot.save(_simulation, _save_path)
	_status.text = ("Save loaded." if load_game else "Colony saved.") if result.ok else result.reason
	if result.ok and load_game:
		_pending.clear()
		_mission_reset = true
		_reset_session()
		_stale = false
		_on_snapshot(_simulation.get_snapshot())
	_play("confirm" if result.ok else "warning")

func _play(id: String) -> void:
	if _mute.button_pressed or DisplayServer.get_name() == "headless":
		return
	_audio.stream = load("res://assets/audio/outpost_" + id + ".wav")
	if _audio.stream != null:
		_audio.play()

func _reset_session() -> void:
	_session = "hud_" + Crypto.new().generate_random_bytes(12).hex_encode()
	_seq = 0

func _refresh_guide() -> void:
	if _tutorial_text == null:
		return
	var objectives := _mission.objectives()
	var complete := _mission.completed_count()
	var title := "FIRST SHIFT" if _mission.training else "COLONY REPAIRS"
	_mission_title.text = "%s · %d/%d" % [title, complete, objectives.size()]
	var active := _mission.current()
	var lines: Array[String] = [title]
	for objective in objectives:
		lines.append(("✓  " if _mission.done.has(objective[0]) else "○  ") + objective[1] + "\n" + objective[2])
	if active.is_empty():
		_mission_text.text = "Shift complete! Salvage returned and new storage is online." if _mission.training else "Repairs complete! Keep monitoring supplies and alerts."
		_mission_action.text = "Start colony repairs" if _mission.training else "Inspect systems"
		lines.append(_mission_text.text)
	else:
		_mission_text.text = active[1] + "\nOpen Guide for the steps and purpose."
		_mission_action.text = "Open " + active[3]
	_tutorial_text.text = "\n\n".join(lines)
	_fit_crew_card.call_deferred()

func _mission_next() -> void:
	var active := _mission.current()
	if active.is_empty() and _mission.training:
		reference_requested.emit()
	else:
		_open_tab("Systems" if active.is_empty() else active[3])

func _task_options() -> Dictionary:
	var keys := _keys(_state.tasks)
	keys.sort_custom(func(a: String, b: String) -> bool:
		var first: Dictionary = _state.tasks[a]
		var second: Dictionary = _state.tasks[b]
		if (first.status in TERMINAL) != (second.status in TERMINAL):
			return first.status not in TERMINAL
		return a < b if first.priority == second.priority else first.priority > second.priority)
	var result := {}
	for id in keys:
		var t: Dictionary = _state.tasks[id]
		var b: Dictionary = _state.buildings.get(t.target_id, {})
		var target: String = _catalog.get(b.get("definition_id"), {}).get("display_name", t.target_id)
		result[id] = "%s · %s · %s" % [t.kind.capitalize(), target, t.status.capitalize()]
	return result

func _building_options(records: Dictionary, is_catalog: bool = false) -> Dictionary:
	var result := {}
	for id in _keys(records):
		var b: Dictionary = records[id]
		result[id] = b.get("display_name", id) if is_catalog else "%s · %s" % [
			_catalog.get(b.definition_id, {}).get("display_name", b.definition_id), id]
	return result

func _catalog_options() -> Dictionary:
	var result := _building_options(_catalog, true)
	for id in result:
		if not _supports(id):
			result[id] += "  (unavailable)"
	return result

func _labels(records: Dictionary) -> Dictionary:
	var result := {}
	for id in _keys(records):
		result[id] = "%s · %s" % [id, records[id].status.capitalize()] if records[id].has("status") else id
	return result

func _fill_options(widget: OptionButton, items: Dictionary) -> void:
	var keep := _selected(widget)
	var keys := items.keys()
	var matches := widget.item_count == keys.size()
	if matches:
		for i in range(keys.size()):
			if widget.get_item_metadata(i) != keys[i]:
				matches = false
				break
	if not matches:
		widget.clear()
		for id in keys:
			widget.add_item(items[id])
			widget.set_item_metadata(widget.item_count - 1, id)
		if items.has(keep):
			widget.select(keys.find(keep))
		elif not keys.is_empty():
			widget.select(0)
	else:
		for i in range(keys.size()):
			widget.set_item_text(i, items[keys[i]])

func _selected(widget: OptionButton) -> String:
	return "" if widget.selected < 0 else str(widget.get_item_metadata(widget.selected))

func _selected_crew() -> Array:
	var ids: Array = []
	for i in _crew.get_selected_items():
		ids.append(_crew.get_item_metadata(i))
	return ids

func _keys(records: Dictionary) -> Array:
	var ids := records.keys()
	ids.sort()
	return ids

# ---------------------------------------------------------------- widgets and theme

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", INK)
	for type in ["Button", "OptionButton", "CheckButton"]:
		t.set_color("font_color", type, INK)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color("#1a1308"))
		t.set_color("font_hover_pressed_color", type, Color("#1a1308"))
		t.set_color("font_disabled_color", type, Color(0.55, 0.53, 0.5, 0.7))
		t.set_font_size("font_size", type, 16)
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _box(Color("#20262d"), 4, 9, 4, Color("#323a43")))
		t.set_stylebox("hover", type, _box(Color("#2a323b"), 4, 9, 4, AMBER.darkened(0.2)))
		t.set_stylebox("pressed", type, _box(AMBER, 4, 9, 4, AMBER))
		t.set_stylebox("hover_pressed", type, _box(AMBER.lightened(0.1), 4, 9, 4, AMBER))
		t.set_stylebox("disabled", type, _box(Color("#181c21"), 4, 9, 4, Color("#22282e")))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 8, 12, 10, Color(1, 1, 1, 0.06)))
	t.set_stylebox("panel", "TabContainer", _box(Color(0, 0, 0, 0.0), 0, 2, 8))
	t.set_stylebox("tab_selected", "TabContainer", _tab(Color("#20262d"), AMBER))
	t.set_stylebox("tab_unselected", "TabContainer", _tab(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	t.set_stylebox("tab_hovered", "TabContainer", _tab(Color("#1a2026"), DIM))
	t.set_color("font_selected_color", "TabContainer", AMBER)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_color("font_hovered_color", "TabContainer", INK)
	t.set_font_size("font_size", "TabContainer", 16)
	t.set_stylebox("panel", "ItemList", _box(Color(0, 0, 0, 0.18), 4, 4, 4))
	t.set_stylebox("selected", "ItemList", _box(Color(AMBER, 0.28), 3, 4, 2))
	t.set_stylebox("selected_focus", "ItemList", _box(Color(AMBER, 0.28), 3, 4, 2))
	t.set_stylebox("hovered", "ItemList", _box(Color(1, 1, 1, 0.06), 3, 4, 2))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_font_size("font_size", "ItemList", 16)
	t.set_constant("v_separation", "ItemList", 5)
	t.set_stylebox("normal", "LineEdit", _box(Color("#0f1317"), 3, 6, 3, Color("#323a43")))
	t.set_stylebox("focus", "LineEdit", _box(Color("#0f1317"), 3, 6, 3, AMBER))
	t.set_color("font_color", "LineEdit", INK)
	t.set_font_size("font_size", "LineEdit", 16)
	t.set_stylebox("panel", "TooltipPanel", _box(Color("#0d1014"), 4, 8, 6, Color("#3a434d")))
	t.set_color("font_color", "TooltipLabel", INK)
	return t

static func _box(color: Color, radius: int, margin_h: float, margin_v: float, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(1)
	return box

static func _tab(color: Color, accent: Color) -> StyleBoxFlat:
	var box := _box(color, 4, 10, 5)
	box.border_color = accent
	box.border_width_bottom = 2
	return box

func _panel(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Mouse buttons and wheel steps that reach a panel (because no child scrolled or pressed)
	# are consumed here, so they never fall through to world selection or camera zoom.
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			panel.accept_event())
	parent.add_child(panel)
	return panel

func _chip(parent: Node, icon_kind: String, title: String, color: Color) -> Label:
	var box := _row(parent, 5)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon := Icon.make(icon_kind, color, 15)
	box.add_child(icon)
	var label := _label(box, title + " —", 13)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	_chips[icon_kind] = {"label": label, "icon": icon}
	return label

func _separator(parent: Node) -> void:
	var line := VSeparator.new()
	line.modulate = Color(1, 1, 1, 0.25)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func _section(parent: Node, title: String) -> void:
	var label := _label(parent, title.to_upper(), 12)
	label.add_theme_color_override("font_color", AMBER)

func _hint(parent: Node, text: String) -> Label:
	var label := _label(parent, text, 12)
	label.add_theme_color_override("font_color", DIM)
	return label

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	scroll.add_child(pad)
	return _column(pad, 8)

func _column(parent: Node, separation: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(box)
	return box

func _row(parent: Node, separation: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(box)
	return box

func _label(parent: Node, value: String = "", size_px: int = 14) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", maxi(size_px, 16))
	parent.add_child(label)
	return label

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	# Keyboard focus stays with the world so Space/WASD keep controlling time and camera.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _option(parent: Node) -> OptionButton:
	var option := OptionButton.new()
	option.fit_to_longest_item = false
	option.focus_mode = Control.FOCUS_NONE
	option.clip_text = true
	parent.add_child(option)
	return option

func _number(parent: Node, title: String, low: float, high: float, step: float, initial: float) -> SpinBox:
	var group := _column(parent, 2)
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var caption := _label(group, title, 11)
	caption.add_theme_color_override("font_color", DIM)
	var input := SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = step
	input.value = initial
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.get_line_edit().custom_minimum_size.x = 56
	group.add_child(input)
	return input
