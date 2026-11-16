extends Control
## I translate the committed colony snapshot into controls and objectives here. I send player intent back as commands and leave the simulation to accept or reject it.

const TutorialMission = preload("res://scripts/ui/tutorial_mission.gd")
const CrewLooks = preload("res://scripts/crew/crew_looks.gd")
const TutorialOverlay = preload("res://scripts/ui/tutorial_overlay.gd")
const SaveSlot = preload("res://scripts/ui/outpost_save_slot.gd")
const Icon = preload("res://scripts/ui/hud_icon.gd")
const RepairPanel = preload("res://scripts/ui/repair_challenge_panel.gd")
const HudShell = preload("res://scripts/ui/colony_hud_shell.gd")
var _skin: RefCounted
const TERMINAL := ["completed", "cancelled", "failed"]
const INK := Color("#e8f1f5")
const DIM := Color("#a8becb")
const AMBER := Color("#64d8ba")
const CYAN := Color("#76cce5")
const DANGER := Color("#ec6a52")
const OK_GREEN := Color("#7fcf7a")
const PANEL := Color("#182a36")
const DRAWER_WIDTH := 320.0
const CREW_WIDTH := 232.0
const TOP_HEIGHT := 40.0

signal reference_requested
signal training_requested
signal crew_selected(crew_id: String)
signal placement_preview(request: Dictionary, result: Dictionary)
## Emitted when the visible world area changes: pixels covered on the left and right.
signal layout_changed(left_px: float, right_px: float)
signal crew_selection_changed(crew_ids: Array)
## Asks the world to show the placement ghost for this definition.
signal placement_requested(definition_id: String, rotation_quarters: int)
signal placement_cancel_requested

var _simulation: RefCounted
var _adapter: RefCounted
var _world: RefCounted
var _catalog: Dictionary = {}
var _save_path := "user://outpost_quick_save.json"
var _state: Dictionary = {}
var _session := ""
var _seq := 0
var _pending: Dictionary = {}
var _tour := TutorialMission.new()
var _tour_enabled := false  # Only the main scene turns the tutorial on.
var _tour_reset := true
var _tour_step: Dictionary = {}
var _tour_step_id := ""
var _tour_failure := {}
var _sim_failed := ""
var _tour_card: PanelContainer
var _tour_progress: Label
var _tour_flash: Label
var _tour_title: Label
var _tour_body: Label
var _tour_recovery: Label
var _tour_move: Label
var _tour_action: Label
var _tour_why: Label
var _tour_buttons: HBoxContainer
var _tour_more: CheckButton
var _status_seen := ""
var _status_until := 0
var _tour_skip: Button
var _tour_primary: Button
var _tour_overlay: Control
var _tour_guide_buttons: HBoxContainer
var _tour_resume: Button
var _world_projector: Callable
var _world_points: Dictionary = {}
var _world_placement := {"active": false, "definition_id": "", "valid": true, "reason": ""}
var _recommended_cell: Array = []
var _recommended_for := ""
var _eva_summary: Label
var _eva_details: VBoxContainer
var _eva_details_toggle: Button
var _suggest_button: Button
var _assign_button: Button
var _stale := false
var _alert_ids: Array = []
var _hud_title: Label
var _clock: Label
var _vitals: Label
var _alerts: Label
var _status: Label
var _tutorial_text: Label
var _mission_tasks: Label
var _mission_hint: Label
var _mission_start: Button
var _tasks_button: Button
var _build_geometry_key := ""
var _build_geometry_result: Dictionary = {}
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
var _inspect_section: VBoxContainer
var _placement_section: VBoxContainer
var _drill_button: Button
var _repair_button: Button
var _repair_text: Label
var _repair_panel: Control
var _camp_level_one := false
var _camp_card: PanelContainer
var _camp_text: Label
var _storm_row: HBoxContainer
var _storm_save: Button
var _storm_keep: Button
var _storm_practice: Button
var _incident_sent := false
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
var _eva_forecast_ok := false
var _eva_forecast_reason := ""
var _alert_list: Label
var _crew_hint: Label
var _drawer_open := true
var _commander_name := ""

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
	_build_geometry_key = ""
	_build_geometry_result.clear()
	_pending.clear()
	_tour_reset = true
	_sim_failed = ""
	_tour_failure = {}
	_alert_ids.clear()
	_reset_session()
	if _simulation == null:
		return
	_simulation.connect("state_changed", _on_snapshot)
	_simulation.connect("game_event", _on_event)
	if is_node_ready():
		_on_snapshot(_simulation.get_snapshot())
		_refresh_capabilities()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_build_top_bar()
	_build_crew_card()
	_build_drawer()
	_build_toast()
	_build_tutorial()
	_build_camp_card()
	_repair_panel = RepairPanel.new()
	_repair_panel.name = "RepairChallenge"
	add_child(_repair_panel)
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	_skin = HudShell.new(self)
	_skin.install()
	resized.connect(_apply_layout)
	_apply_layout()
	if _simulation != null:
		_on_snapshot(_simulation.get_snapshot())
	else:
		_refresh_guide()
	_refresh_capabilities()

# ---------------------------------------------------------------- layout

func _process(_delta: float) -> void:
	if _status == null:
		return
	if _tour.active and _status.text.begins_with("Tutorial hidden"):
		_status.text = "Tutorial resumed."
	if _status.text != _status_seen:
		_status_seen = _status.text
		_status_until = Time.get_ticks_msec() + 4500
	_toast.visible = not _status.text.is_empty() and Time.get_ticks_msec() < _status_until
	if _status.text.begins_with("Set Time Scale") or _status.text.begins_with("Queued: Set Time Scale"):
		_toast.visible = false
	if _skin != null: _skin.refresh()

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
	for entry in [[0, "pause", "Pause (Space)"], [1, ">", "Play (1)"], [5, ">>", "Fast (2)"], [20, ">>>", "Fastest (3)"]]:
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
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(space)
	_tasks_button = _button(head, "Tasks", func():
		_open_tab("Guide")
		_tour_refresh()
		_refresh_guide())
	_tasks_button.tooltip_text = "Mission objectives, progress and colony jobs"
	_mission_hint = _label(body, "", 12)
	_mission_hint.add_theme_color_override("font_color", AMBER)
	_crew_hint = _label(body, "Ctrl/Shift adds crew", 16)
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
		_tour_refresh()
		_fit_drawer.call_deferred())
	_drawer_body.add_child(_tabs)

	var jobs := _page("Jobs")
	_section(jobs, "Job")
	_tasks = _option(jobs)
	_tasks.item_selected.connect(func(_i: int): _refresh_selection())
	_task_text = _label(jobs, "", 13)
	_priority = _number(jobs, "Priority (higher first)", 0, 100, 1, 50)
	var job_actions := _row(jobs, 6)
	_suggest_button = _button(job_actions, "Suggest crew", _suggest)
	_suggest_button.tooltip_text = "Select the recommended available astronauts"
	_assign_button = _button(job_actions, "Assign selected", _assign)
	_assign_button.tooltip_text = "Assign the astronauts selected in the crew roster"
	var cancel := _button(jobs, "Cancel job", func():
		var id := _selected(_tasks)
		if not id.is_empty():
			_send("cancel_task", {"task_id": id}))
	cancel.tooltip_text = "Cancelling unfinished construction refunds its prepaid materials"
	_hint(jobs, "Pick astronauts in the crew roster, then assign them. Repairs restore damaged modules; construction finishes placed modules.")

	var build := _page("Build")
	_inspect_section = _column(build, 8)
	_section(_inspect_section, "Selected equipment")
	_buildings = _option(_inspect_section)
	_buildings.item_selected.connect(func(_i: int): _refresh_selection())
	_building_text = _label(_inspect_section, "", 13)
	_toggle_building = _button(_inspect_section, "Toggle module", _toggle)
	var repair_row := _row(_inspect_section, 6)
	_drill_button = _button(repair_row, "Fault drill", _fault_drill)
	_drill_button.tooltip_text = "Training drill: this module develops a real fault. Its repair is a hands-on challenge."
	_repair_button = _button(repair_row, "Start repair", _start_repair)
	_repair_button.tooltip_text = "The selected astronaut (or your best free engineer) attempts the repair. A failed attempt locks this component for one mission day."
	_repair_text = _label(_inspect_section, "", 13)
	_placement_section = _column(build, 8)
	_section(_placement_section, "Choose what to build")
	_catalog_menu = _option(_placement_section)
	_catalog_menu.item_selected.connect(func(_i: int): _preview_build())
	_place_on_map = _button(_placement_section, "Choose a cell on the map", func():
		placement_requested.emit(_selected(_catalog_menu), int(_rotation.value)))
	_place_on_map.tooltip_text = "Shows the module outline under the cursor. Click to place, R rotates, Esc cancels."
	var coords := _row(_placement_section, 6)
	_x = _number(coords, "Cell X", 0, 100000, 1, 0)
	_z = _number(coords, "Cell Z", 0, 100000, 1, 0)
	_rotation = _number(coords, "Turns", 0, 3, 1, 0)
	for field in [_x, _z, _rotation]:
		field.value_changed.connect(func(_v: float): _preview_build())
	_build_preview = _label(_placement_section, "", 13)
	_place = _button(_placement_section, "Place at these coordinates", func(): _send("place_building", _placement()))

	var eva := _page("EVA")
	_section(eva, "Plan a salvage trip")
	_hint(eva, "Uses the astronauts selected in the crew list.")
	_sites = _option(eva)
	_sites.item_selected.connect(func(_i: int): _preview_eva())
	# Plain-language safety summary and Launch stay at the top; editable supply numbers and
	# the per-phase forecast live behind a toggle so Launch never falls below the fold.
	_eva_summary = _label(eva, "", 16)
	_launch = _button(eva, "Launch expedition", func(): _send("start_eva", _eva_request()))
	_eva_details_toggle = _button(eva, "Show supplies and forecast details", func():
		_eva_details.visible = not _eva_details.visible
		_eva_details_toggle.text = "Hide supplies and forecast details" if _eva_details.visible else "Show supplies and forecast details"
		_fit_drawer.call_deferred())
	_eva_details = _column(eva, 6)
	_eva_details.visible = false
	var supplies := _row(_eva_details, 6)
	_work = _number(supplies, "Work s", 1, 100000, 1, 20)
	_oxygen = _number(supplies, "O₂ kg each", 0, 1000, 0.00001, 0.12)
	_battery = _number(supplies, "kWh each", 0, 1000, 0.00001, 0.006)
	for field in [_work, _oxygen, _battery]:
		field.value_changed.connect(func(_v: float): _preview_eva())
	_eva_forecast = _label(_eva_details, "", 12)
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
	_section(onboarding, "Missions & tasks")
	_mission_start = _button(onboarding, "Start mission 2", _start_independent)
	_tutorial_text = _label(onboarding, "", 16)
	_mission_tasks = _label(onboarding, "", 16)
	_button(onboarding, "Open colony jobs", func(): _open_tab("Jobs"))
	_tour_guide_buttons = _row(onboarding, 6)
	_tour_resume = _button(_tour_guide_buttons, "Resume tutorial", func():
		_tour_enabled = true
		_tour.active = true
		_status.text = "Tutorial resumed."
		_tour_refresh())
	var restart := _button(_tour_guide_buttons, "Restart tutorial", func():
		_tour.restart()
		training_requested.emit())
	restart.tooltip_text = "Starts the tutorial again from a fresh training colony."
	_section(onboarding, "Controls")
	_hint(onboarding, "Pause to plan; commands also resolve while paused. Use > to play, >> for fast, or >>> for fastest. F2 starts training; F3 starts the reference colony. After repairs, complete your first independent shift. F1 shows diagnostics.")
	_hint(onboarding, "Camera: edge scrolling or WASD pans; middle-drag rotates/tilts; Q/E rotates; Home/End tilts; wheel or Z/X zooms; F recentres. Right-click cancels; 1/2/3 sets speed. Click modules, sites or astronauts to inspect them.")

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
	var drawer_width := DRAWER_WIDTH
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
	_tour_refresh.call_deferred()
	if _skin != null: _skin.layout()

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
	if _skin != null: _crew_card.visible = false
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
	if _skin != null:
		_crew_card.visible = true
		_drawer_open = false
		_apply_layout()
	for index in range(_crew.item_count):
		if _crew.get_item_metadata(index) == id:
			_crew.select(index)
			_refresh_selection()
			return

func select_building(id: String) -> void:
	## World selection of a module: inspect it in the Build drawer.
	if _buildings == null or id.is_empty():
		return
	if _skin != null:
		_inspect_section.visible = true
		_placement_section.visible = false
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
			_tour_reset = true
			_reset_session()
	elif tick != int(_state.clock.tick_index):
		_stale = false
	elif snapshot.buildings != _state.buildings or snapshot.expeditions != _state.expeditions \
			or snapshot.tasks != _state.tasks:
		_stale = true
	_state = snapshot
	if _simulation != null and _simulation.has_method("get_capabilities"):
		_hud_title.text = "TRAINING · SYNTHETIC" if snapshot.campaign_id.begins_with("fixture_") else "REFERENCE COLONY"
	var scale_value: int = int(snapshot.clock.time_scale)
	var elapsed := int(snapshot.clock.get("elapsed_s", tick))
	_clock.text = "T+ %02d:%02d · %s" % [elapsed / 3600, (elapsed / 60) % 60, {0: "Paused", 1: ">", 5: ">>", 20: ">>>"}.get(scale_value, ">")]
	_clock.tooltip_text = "Elapsed colony time (hours:minutes)"
	for key in _speed_buttons:
		_speed_buttons[key].set_pressed_no_signal(key == scale_value)
	_refresh_roster()
	_fill_options(_tasks, _task_options())
	_fill_options(_buildings, _building_options(snapshot.buildings))
	_fill_options(_catalog_menu, _catalog_options())
	_fill_options(_sites, _labels(snapshot.sites))
	var known_trips := _trips.item_count
	_fill_options(_trips, _labels(snapshot.expeditions))
	if _trips.item_count > known_trips and known_trips > 0:
		# A newly launched trip becomes the one shown (and recalled) in the EVA tab.
		_trips.select(_trips.item_count - 1)
	_refresh_life_support()
	_refresh_selection()
	_preview_build()
	_tour_refresh()
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

func _crew_name(value: String) -> String:
	return CrewLooks.display_name(value)

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
		_crew.set_item_text(i, "%s  ·  %s" % [_crew_name(member.display_name), "Inside" if member.status == "idle" and member.location_kind == "base" else member.status.capitalize()])
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
			skills.append("%s: %d%%" % [skill.capitalize(), roundi(c.skills[skill] * 100)])
		var ranked: Array = c.skills.keys()
		ranked.sort_custom(func(a: String, b: String): return float(c.skills[a]) > float(c.skills[b]))
		var rows: Array[String] = ["Health %d%% · Fatigue %d%%" % [roundi(c.health * 100), roundi(c.fatigue * 100)], "Stress %d%%" % roundi(c.stress * 100)]
		var injury: Dictionary = repair_state().get("injuries", {}).get(c.id, {})
		if not injury.is_empty():
			var left: int = maxi(0, int(injury.recover_tick) - int(_state.clock.tick_index))
			rows.append("INJURED (electrical shock): off duty, recovering for %d d %02d h" % [left / 86400, (left % 86400) / 3600])
		for skill in ranked.slice(0, 2):
			rows.append("%s: %d%%" % [str(skill).capitalize(), roundi(c.skills[skill] * 100)])
		details.append("\n".join(rows))
		_crew_text.tooltip_text = "\n".join(skills)
	var chosen := _selected_crew()
	if chosen.size() > 1:
		var names: Array[String] = []
		for id in chosen:
			names.append(_crew_name(_state.crew[id].display_name))
		details = ["%d selected: %s" % [chosen.size(), ", ".join(names)]]
	_crew_text.text = "Select an astronaut to inspect their skills." if details.is_empty() else "\n".join(details)
	_fit_crew_card.call_deferred()
	crew_selection_changed.emit(_selected_crew())
	_tour_refresh.call_deferred()
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
	_refresh_repair(building)
	_refresh_camp_card()
	var trip: Dictionary = _state.expeditions.get(_selected(_trips), {})
	var expedition_job: Dictionary = _state.tasks.get(trip.get("task_id"), {})
	_recall.disabled = trip.is_empty() or trip.get("status") in ["returning", "completed", "failed"]
	var suit_lines: Array[String] = []
	for id in _keys(trip.get("suit_stores", {})):
		var suit: Dictionary = trip.suit_stores[id]
		suit_lines.append("%s: %.5f kg O₂ · %.5f kWh" % [_crew_name(_state.crew[id].display_name), suit.oxygen_kg, suit.battery_kwh])
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
		# Flood-fill placement checks depend on geometry, not changing resource
		# balances or solar output. Affordability is still checked every refresh.
		var geometry: Array = []
		for id in _keys(_state.buildings):
			var b: Dictionary = _state.buildings[id]
			geometry.append([id, b.definition_id, b.cell, b.rotation_quarters, b.lifecycle])
		var blocked: Variant = _world.blocked_cells(_state) if _world.has_method("blocked_cells") else []
		var key := JSON.stringify([request, _state.map, geometry, _state.get("sites", {}), _state.get("expeditions", {}), blocked])
		if key != _build_geometry_key:
			_build_geometry_result = _world.validate_placement(request, _state).duplicate(true)
			_build_geometry_key = key
		result = _build_geometry_result.duplicate(true)
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
	_tour_refresh.call_deferred()
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
	_eva_forecast_ok = r.ok
	_eva_forecast_reason = "" if r.ok else str(r.reason)
	if r.ok and r.has("remaining"):
		var o2 := 100.0 * float(r.remaining.oxygen_kg) / maxf(_oxygen.value, 1e-9)
		var power := 100.0 * float(r.remaining.battery_kwh) / maxf(_battery.value, 1e-9)
		_eva_summary.text = "Safe to launch. Each astronaut should come home with about %d%% of their suit oxygen and %d%% of their suit battery left." % [roundi(o2), roundi(power)]
		_eva_summary.add_theme_color_override("font_color", OK_GREEN)
	else:
		_eva_summary.text = "Not ready: " + str(r.reason)
		_eva_summary.add_theme_color_override("font_color", INK)
	_tour_refresh()

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

func _build_camp_card() -> void:
	_camp_card = _panel(self)
	_camp_card.name = "CampObjective"
	_camp_card.anchor_left = 0.5
	_camp_card.anchor_right = 0.5
	_camp_card.offset_left = -330
	_camp_card.offset_right = 330
	_camp_card.offset_top = 58
	_camp_card.add_theme_stylebox_override("panel", _box(Color(0.06, 0.07, 0.085, 0.94), 8, 12, 8, Color(CYAN, 0.8)))
	var body := _column(_camp_card, 6)
	_camp_text = _label(body, "", 14)
	_storm_row = _row(body, 8)
	_storm_save = _button(_storm_row, "Save power for breathing", func(): _choose_storm("save_power"))
	_storm_save.tooltip_text = "The farm is switched off during the storm. This costs food production."
	_storm_keep = _button(_storm_row, "Keep the farm running", func(): _choose_storm("keep_farm"))
	_storm_keep.tooltip_text = "Nothing is switched off. Batteries must cover the missing solar power."
	_storm_practice = _button(body, "Storm practice (optional)", func(): _send("start_storm_practice", {}))
	_storm_practice.tooltip_text = "Starts the same real dust storm now instead of waiting for a random one."
	_camp_card.visible = false

func _enable_storms() -> void:
	if _simulation != null and _simulation.has_method("enable_dust_storms"): _simulation.enable_dust_storms()
	if _simulation != null and _simulation.has_method("enable_radiation"): _simulation.enable_radiation()

func _choose_storm(response: String) -> void:
	var was_forecast: bool = storm_state().status == "forecast"
	_send("set_storm_response", {"response": response})
	if was_forecast: _time(1)

func storm_state() -> Dictionary:
	if _simulation == null or not _simulation.has_method("get_storm_state"): return {"enabled": false, "status": "idle"}
	return _simulation.get_storm_state()

func camp_objective() -> Dictionary:
	## The next step of the camp mission, read from committed state. Never acknowledgement-only.
	var farm: Dictionary = {}
	for building in _state.get("buildings", {}).values():
		if "greenhouse" in str(building.definition_id): farm = building
	var view := repair_state()
	var open_fault: Dictionary = {}
	var locked_fault: Dictionary = {}
	for fault in view.faults.values():
		if fault.status == "open": open_fault = fault
		elif fault.status == "locked": locked_fault = fault
	var paused: bool = int(_state.get("clock", {}).get("time_scale", 0)) == 0
	var run_hint := " Press > to run time." if paused else ""
	if farm.is_empty():
		var resources: Dictionary = _state.get("resources", {})
		if float(resources.get("alloy", {}).get("amount", 0.0)) < 8.0 or float(resources.get("electronics", {}).get("amount", 0.0)) < 3.0:
			return {"step": 1, "text": "Build the farm wing: you need 8 Alloy and 3 Electronics. Cancel another construction job in Jobs to get its materials back."}
		return {"step": 1, "text": "Build the farm wing. Open the Build tab, choose Greenhouse, press “Choose a cell on the map” and click free ground beside the camp. If a spot is refused, pick open ground away from other modules."}
	if farm.lifecycle == "constructing":
		var job: Dictionary = _state.get("tasks", {}).get(farm.construction_task_id, {})
		if job.get("assigned_crew_ids", []).is_empty():
			return {"step": 2, "text": "Assign a construction crew. Open the Jobs tab, choose the Greenhouse job, press Suggest crew, then Assign selected."}
		return {"step": 3, "text": "Your builder is walking to the site and building it (%d%%)." % roundi(float(farm.construction_progress) * 100.0) + run_hint}
	var tend: Dictionary = {}
	for task in _state.get("tasks", {}).values():
		if task.kind == "farm" and task.status not in TERMINAL: tend = task
	if view.faults.is_empty() and not tend.is_empty() and tend.assigned_crew_ids.is_empty() and float(farm.operating_fraction) > 0.0 and not _incident_sent:
		return {"step": 4, "text": "The farm is growing. Give it a specialist: open Jobs, choose the Farm job, press Suggest crew (it picks your best botanist), then Assign selected. Tending brings in a harvest."}
	if view.faults.is_empty():
		if float(farm.operating_fraction) <= 0.0:
			return {"step": 4, "text": "The farm is built. It needs electricity, water and CO2 to grow food: check the Systems tab." + run_hint}
		return {"step": 4, "text": "The farm is growing food from water and CO2. One greenhouse adds to your stored food; it cannot feed the whole crew alone." + run_hint}
	if view.session != null: return {"step": 5, "text": "Repair in progress."}
	if not open_fault.is_empty():
		var target: Dictionary = _state.buildings.get(open_fault.building_id, {})
		var name: String = str(_catalog.get(target.get("definition_id", ""), {}).get("display_name", "module"))
		return {"step": 5, "text": "Incident: the %s has a fault. Choose a repair astronaut in the CREW list (engineers get an easier repair), select the %s in the Build tab, then press Start repair." % [name, name]}
	if not locked_fault.is_empty() and int(locked_fault.locked_until_tick) > int(view.tick_index):
		var safety := camp_stability()
		if not safety.ok:
			return {"step": 5, "text": "Setup complete, but the emergency is NOT resolved: %s. The failed repair is locked for one mission day. Free up power (disable the farm in Build), then retry the repair when the lock ends." % "; ".join(safety.reasons)}
		return {"step": 6, "text": "The repair failed, so that module is offline and locked for one mission day. Life support is still fully powered and oxygen covers the lock, so Camp Level 1 is reached. Retry the repair when the lock ends."}
	return {"step": 6, "text": "Camp Level 1 established. Your farm is growing food and the fault is handled. Watch for dust storms."}

func _refresh_camp_card() -> void:
	if _camp_card == null or _state.is_empty(): return
	var camp_colony: bool = _catalog.has("greenhouse_mk1") and _simulation != null and _simulation.has_method("get_repair_state")
	_camp_card.visible = camp_colony and not _repair_panel.is_open()
	if not camp_colony: return
	var objective := camp_objective()
	var view := repair_state()
	# The first incident happens once, at a committed milestone: the farm is producing.
	var producing := false
	for building in _state.buildings.values():
		if "greenhouse" in str(building.definition_id) and building.lifecycle == "commissioned" and float(building.operating_fraction) > 0.0: producing = true
	var tended := false
	for task in _state.tasks.values():
		if task.kind == "farm" and (task.status == "completed" or not task.assigned_crew_ids.is_empty()): tended = true
	if producing and tended and view.faults.is_empty() and not _incident_sent:
		_incident_sent = true
		for id in _keys(_state.buildings):
			if "battery" in str(_state.buildings[id].definition_id) and _state.buildings[id].lifecycle == "commissioned":
				_send("trigger_fault_drill", {"building_id": id})
				select_building(id)
				break
	elif view.faults.is_empty() and not producing: _incident_sent = false
	var lines: Array[String] = ["CAMP MISSION · step %d of 6\n%s" % [int(objective.step), str(objective.text)]]
	for crew_id in view.get("injuries", {}):
		lines.append("%s is injured and off duty, so repairs fall to your next-best engineer." % _crew_name(str(_state.crew[crew_id].display_name)))
	var storm := storm_state()
	# The simulation is mid-update inside this callback, so enabling waits one idle frame.
	if camp_progress().level_one and not storm.enabled: _enable_storms.call_deferred()
	var now: int = int(_state.clock.tick_index)
	var facts := "Solar %.1f kW · Battery %d%% · Oxygen %.0f kg" % [float(_state.power.generated_kw),
		roundi(100.0 * float(_state.power.battery_stored_kwh) / maxf(0.001, float(_state.power.battery_capacity_kwh))), float(_state.resources.oxygen_kg.amount)]
	_storm_row.visible = storm.status in ["forecast", "active"]
	_storm_practice.visible = storm.enabled and storm.status in ["idle", "cooldown"]
	if storm.status == "forecast":
		var lead: int = maxi(0, int(storm.arrival_tick) - now)
		lines.append("DUST STORM WARNING · arrives in %d min\nA dust storm is approaching. Your solar panels will make less electricity (about a quarter). Less sunlight means less solar electricity; batteries help for a while. Keep the farm growing, or save power for breathing equipment? Then press > to continue.\n%s" % [ceili(lead / 60.0), facts])
	elif storm.status == "active":
		var left: int = maxi(0, int(storm.end_tick) - now)
		var drain: float = -float(_state.resources.energy_kwh.net_rate_per_s) * 3600.0
		var estimate := "Battery lasts about %.1f h at this rate." % (float(_state.power.battery_stored_kwh) / drain) if drain > 0.0001 else "Battery is not draining right now."
		lines.append("DUST STORM ACTIVE · %d h %02d min left · solar panels at 25%% (game setting)\nChoice: %s. %s\n%s" % [left / 3600, (left % 3600) / 60,
			"saving power, the farm is off and grows no food" if storm.response == "save_power" else "the farm keeps running on batteries", estimate, facts])
	elif storm.status == "cooldown" and int(storm.count) > 0 and now - (int(storm.cooldown_until_tick) - 43200) < 1800:
		lines.append("The dust storm has cleared. Solar power and normal priorities are back.")
	if storm.status in ["forecast", "active"]:
		_storm_save.disabled = storm.response == "save_power"
		_storm_keep.disabled = storm.response == "keep_farm"
	_camp_text.text = "\n".join(lines)

func camp_progress() -> Dictionary:
	## Level 1 is read from committed simulation state only. Nothing here grants progress.
	var farm_built := false
	var farm_running := false
	for building in _state.get("buildings", {}).values():
		if "greenhouse" in str(building.definition_id) and building.lifecycle == "commissioned":
			farm_built = true
			if float(building.operating_fraction) > 0.0: farm_running = true
	var view := repair_state()
	var drilled: bool = not view.faults.is_empty()
	var repaired := false
	var locked := false
	for fault in view.faults.values():
		if fault.status == "resolved": repaired = true
		elif fault.status == "locked": locked = true
	# A failed, locked repair only counts when the camp is demonstrably safe without it.
	var stable := camp_stability()
	var handled: bool = drilled and view.session == null and ((repaired and not locked) or (locked and stable.ok))
	var rows: Array = [
		{"title": "Build a greenhouse (Build tab) and assign a builder (Jobs tab)", "done": farm_built},
		{"title": "Run time until the farm produces food", "done": farm_running},
		{"title": "An equipment fault is reported (it happens once the farm is staffed)", "done": drilled},
		{"title": "Repair it hands-on, or stabilize the colony under the lockout", "done": handled}]
	var hint := "Level 1 needs a producing farm and one handled fault."
	if farm_running and handled:
		hint = "Level 1 reached. The fault was repaired." if repaired and not locked else "Level 1 reached on backup equipment: life support is fully powered and oxygen covers the lockout. Retry the locked repair after one mission day."
	elif farm_built and locked and not stable.ok:
		hint = "Setup complete, emergency unresolved: " + "; ".join(stable.reasons) + "."
	return {"level_one": farm_running and handled, "rows": rows, "hint": hint, "stable": stable.ok, "emergency": farm_built and locked and not stable.ok}

func camp_stability() -> Dictionary:
	## Declared safety test for running on backup equipment during a one-day repair lock:
	## no oxygen/CO2/power-shortfall alert, every life-support module fully powered, and
	## oxygen not forecast to run out within the 24-hour lock.
	var reasons: Array[String] = []
	for alert in _state.get("alerts", []):
		if alert.code == "low_oxygen": reasons.append("oxygen is running low")
		elif alert.code == "co2_high": reasons.append("CO2 is too high")
	for building in _state.get("buildings", {}).values():
		var id := str(building.definition_id)
		if not (id.begins_with("water") or id.begins_with("co2")) or building.lifecycle != "commissioned" or not building.enabled: continue
		if float(building.power_served_kw) + 1e-9 < float(building.power_requested_kw):
			reasons.append("life support is not getting full power")
			break
	var oxygen: Dictionary = _state.get("resources", {}).get("oxygen_kg", {})
	if oxygen.get("forecast_empty_s") != null and float(oxygen.forecast_empty_s) < 86400.0:
		reasons.append("oxygen will not last through the one-day lock")
	if float(oxygen.get("amount", 0.0)) <= 0.0: reasons.append("no oxygen reserve")
	return {"ok": reasons.is_empty(), "reasons": reasons}

func repair_state() -> Dictionary:
	if _simulation == null or not _simulation.has_method("get_repair_state"): return {"faults": {}, "session": null, "tick_index": 0}
	return _simulation.get_repair_state()

func _refresh_repair(building: Dictionary) -> void:
	if _repair_text == null: return
	var view := repair_state()
	var fault: Dictionary = view.faults.get(building.get("id", ""), {})
	var unresolved := false
	for other in view.faults.values():
		if other.status != "resolved": unresolved = true
	var supported: bool = _simulation != null and _simulation.has_method("get_repair_state")
	_drill_button.disabled = not supported or building.is_empty() or building.get("lifecycle") != "commissioned" or unresolved
	_repair_button.disabled = not supported or fault.is_empty() or fault.status == "resolved" or view.session != null
	if fault.is_empty(): _repair_text.text = "No fault on this module."
	elif fault.status == "open": _repair_text.text = "FAULT: needs a hands-on repair (%s)." % ("rewire the circuit" if fault.kind == "circuit" else "calibrate the tracker")
	elif fault.status == "locked":
		var wait: int = maxi(0, int(fault.locked_until_tick) - int(view.tick_index))
		_repair_text.text = "Repair LOCKED after a failed attempt. Retry in %d h %02d min. No astronaut can bypass this." % [wait / 3600, (wait % 3600) / 60] if wait > 0 else "Lockout over: the repair can be retried."
	else: _repair_text.text = "Fault repaired (%d attempt%s)." % [int(fault.attempts), "" if int(fault.attempts) == 1 else "s"]

func _fault_drill() -> void:
	var id := _selected(_buildings)
	if not id.is_empty(): _send("trigger_fault_drill", {"building_id": id})

func repair_operator() -> String:
	## The selected idle astronaut, else the free astronaut with the best engineering skill.
	for id in _selected_crew():
		if _state.crew.get(id, {}).get("status") == "idle": return id
	var best := ""
	for id in _keys(_state.get("crew", {})):
		var member: Dictionary = _state.crew[id]
		if member.status != "idle" or member.location_kind != "base": continue
		if best.is_empty() or float(member.skills.get("engineering", 0.0)) > float(_state.crew[best].skills.get("engineering", 0.0)): best = id
	return best

func _start_repair() -> void:
	var id := _selected(_buildings)
	var crew_id := repair_operator()
	if id.is_empty() or crew_id.is_empty():
		_status.text = "No free astronaut is available for the repair."
		return
	_send("start_repair_challenge", {"building_id": id, "crew_id": crew_id})
	_simulation.process_pending_commands()

func _repair_send(type: String, payload: Dictionary) -> void:
	# Challenge inputs go straight to the simulation and resolve at once; they never
	# carry a result, only what the player pressed.
	if _simulation == null: return
	_seq += 1
	_simulation.submit_command({"contract_version": "2.0.0", "command_id": "%s:%06d" % [_session, _seq], "type": type, "payload": payload})
	_simulation.process_pending_commands()

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
		_tour_note_failure(str(result.reason))
		_play("warning")

func _on_event(event: Dictionary) -> void:
	if event.type == "command_result" and _pending.has(event.data.command_id):
		var type: String = _pending[event.data.command_id]
		_pending.erase(event.data.command_id)
		_status.text = _explain(type) + " accepted." if event.data.success else event.data.reason
		if not event.data.success:
			_tour_note_failure(str(event.data.reason))
		_play("confirm" if event.data.success else "warning")
	elif event.type == "command_result" and not event.data.success:
		# Commands from the world (map placement) are not tracked as pending HUD commands.
		_status.text = str(event.data.reason)
		_tour_note_failure(str(event.data.reason))
	elif event.type == "repair_started":
		var target: Dictionary = _state.get("buildings", {}).get(event.data.building_id, {})
		var member: Dictionary = _state.get("crew", {}).get(event.data.crew_id, {})
		_repair_panel.open(_simulation, _repair_send, event.data.building_id,
			str(_catalog.get(target.get("definition_id", ""), {}).get("display_name", "module")), _crew_name(str(member.get("display_name", "Astronaut"))))
		move_child(_repair_panel, get_child_count() - 1)
	elif event.type in ["fault_started", "repair_succeeded", "repair_failed"]:
		_status.text = {"fault_started": "Fault reported. Open Build, select the module and press Start repair.",
			"repair_succeeded": "Repair complete: the module is back to full condition.",
			"repair_failed": "Repair failed: the module is offline and locked for one mission day."}[event.type]
		if event.type == "repair_failed" and repair_state().get("injuries", {}).has(event.entity_ids[1]):
			_status.text += " The operator was injured and is off duty."
		_play("confirm" if event.type == "repair_succeeded" else "warning")
	elif event.type in ["building_commissioned", "eva_returned", "task_completed"]:
		_status.text = _explain(event.type)
		_play("confirm")

func load_saved_game() -> void:
	## Title screen "Load Game": restore the quick save through the same path as the Load button.
	_save_load(true)

func _save_load(load_game: bool) -> void:
	if _simulation == null:
		return
	var result := SaveSlot.load_slot(_simulation, _save_path) if load_game else SaveSlot.save(_simulation, _save_path)
	_status.text = ("Save loaded." if load_game else "Colony saved.") if result.ok else result.reason
	if result.ok and load_game:
		_pending.clear()
		_tour_reset = true
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
	if _tour.active:
		_tutorial_text.text = "Complete your first independent shift: keep the crew alive and finish with oxygen, water and battery reserves. Check Systems and respond to alerts." if _tour.finished else "Follow the highlighted control and the current lesson. Details expands the explanation. Skip tutorial enters free play; Resume returns to your current step."
	else:
		_tutorial_text.text = "Tutorial complete. You can play freely or restart from a fresh training colony." if _tour.finished else "Tutorial hidden. Resume where you left off, or restart from a fresh training colony."
	_tour_resume.visible = not _tour.active and not _tour.finished
	if _state.is_empty() or _mission_tasks == null:
		return
	var ctx := _tour_ctx()
	var summary := _tour.task_summary(ctx)
	var ready := _tour.independent_ready(ctx)
	_mission_start.visible = not ctx.training and not _tour.finished
	_mission_start.disabled = not ready
	_mission_start.tooltip_text = "Ready: start your six-hour independent shift." if ready else "Finish the starting repair jobs in Jobs to unlock mission 2."
	var lines: Array[String] = [summary.title, summary.action, ""]
	if not ctx.training and not _tour.finished:
		lines.insert(1, "Mission 2 is ready. Press Start mission 2." if ready else "Mission 2 unlocks after the starting repairs are complete. Open colony jobs to assign crew.")
	for row in summary.checklist:
		lines.append(("✓ " if row.done else "→ " if row.current else "□ ") + str(row.title))
	var camp := camp_progress()
	var camp_lines: Array[String] = ["CAMP LEVEL 1 · ESTABLISHED" if camp.level_one else ("CAMP · SETUP COMPLETE, EMERGENCY UNRESOLVED" if camp.emergency else "CAMP · REACH LEVEL 1")]
	for row in camp.rows: camp_lines.append(("✓ " if row.done else "□ ") + str(row.title))
	camp_lines.append(str(camp.hint) + "\n")
	lines = camp_lines + lines
	if camp.level_one and not _camp_level_one:
		_camp_level_one = true
		_status.text = "Camp Level 1 established: the farm is producing and the fault was handled."
		_play("confirm")
	elif not camp.level_one: _camp_level_one = false
	lines.append("\nCOLONY JOBS")
	var jobs := _task_options()
	for label in jobs.values(): lines.append("• " + str(label))
	if jobs.is_empty(): lines.append("No colony jobs queued.")
	_mission_tasks.text = "\n".join(lines)
	_tasks_button.text = "Tasks • Ready" if ready else "Tasks"
	_mission_hint.text = "Mission 2 ready · open Tasks" if ready else str(summary.title)

func _start_independent() -> void:
	if not _tour.independent_ready(_tour_ctx()):
		return
	_tour_enabled = true
	_tour.acknowledge("debrief")
	_time(0)
	_tour_refresh()

# ---------------------------------------------------------------- tutorial mission

func enable_tutorial(enabled: bool = true) -> void:
	## The main scene opts in. Test harnesses that bind the HUD directly stay tutorial-free.
	_tour_enabled = enabled
	_tour.restart()
	_tour.active = enabled
	_tour_reset = true
	_tour_refresh()

func set_commander(display_name: String) -> void:
	## The player's astronaut name from the front end; the tutorial greets them by it.
	_commander_name = display_name
	_tour_refresh()

func on_simulation_failed(result: Dictionary) -> void:
	_sim_failed = str(result.get("reason", "unknown error"))
	_tour_refresh()

func set_world_projector(projector: Callable) -> void:
	_world_projector = projector

func set_world_points(points: Dictionary) -> void:
	_world_points = points.duplicate()

func set_world_placement(active: bool, definition_id: String, result: Dictionary) -> void:
	_world_placement = {"active": active, "definition_id": definition_id,
		"valid": bool(result.get("valid", true)), "reason": str(result.get("reason", ""))}
	_tour_refresh.call_deferred()

func tutorial_step() -> Dictionary:
	return _tour_step.duplicate(true)

func tutorial_press(id: String) -> void:
	## Same handler the card buttons use; exposed for tests and keyboard shortcuts.
	_tour_button(id)

func _tour_note_failure(reason: String) -> void:
	_tour_failure = {"step": _tour_step_id, "text": reason}
	_tour_refresh.call_deferred()

func _build_tutorial() -> void:
	_tour_card = _panel(self)
	_tour_card.name = "TutorialCard"
	_tour_card.add_theme_stylebox_override("panel", _box(Color(0.06, 0.07, 0.085, 0.96), 10, 18, 14, Color(AMBER, 0.85)))
	var body := _column(_tour_card, 6)
	_tour_progress = _label(body, "", 14)
	_tour_progress.add_theme_color_override("font_color", DIM)
	_tour_flash = _label(body, "", 16)
	_tour_flash.add_theme_color_override("font_color", OK_GREEN)
	_tour_title = _label(body, "", 19)
	_tour_title.add_theme_color_override("font_color", AMBER)
	_tour_body = _label(body, "", 17)
	_tour_recovery = _label(body, "", 17)
	_tour_recovery.add_theme_color_override("font_color", Color("#ffb08a"))
	_tour_move = _label(body, "YOUR MOVE", 13)
	_tour_move.add_theme_color_override("font_color", AMBER)
	_tour_action = _label(body, "", 17)
	_tour_action.add_theme_color_override("font_color", Color.WHITE)
	_tour_why = _label(body, "", 15)
	_tour_why.add_theme_color_override("font_color", DIM)
	var row := _row(body, 8)
	_tour_buttons = _row(row, 8)
	_tour_more = CheckButton.new()
	_tour_more.text = "Details"
	_tour_more.focus_mode = Control.FOCUS_NONE
	row.add_child(_tour_more)
	_tour_more.toggled.connect(func(_on: bool): _tour_refresh())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_tour_skip = _button(row, "Skip tutorial", func(): _tour_button("skip"))
	_tour_skip.flat = true
	_tour_skip.add_theme_color_override("font_color", DIM)
	_tour_skip.tooltip_text = "Hide the tutorial and play freely. Resume or restart it from the Guide tab."
	_tour_card.visible = false
	_tour_overlay = TutorialOverlay.new()
	_tour_overlay.name = "TutorialHighlight"
	add_child(_tour_overlay)
	_tour_overlay.resolver = _tour_targets
	_tour_overlay.visible = false

func _tour_ctx() -> Dictionary:
	var training: bool = str(_state.get("campaign_id", "")).begins_with("fixture_")
	var storage_id := ""
	for id in _keys(_catalog):
		if id.contains("storage"):
			storage_id = id
			break
	var names := {}
	for id in _state.get("crew", {}):
		names[id] = _crew_name(_state.crew[id].display_name)
	var catalog_names := {}
	for id in _catalog:
		catalog_names[id] = _catalog[id].get("display_name", id)
	return {"snapshot": _state, "training": training,
		"tab": _tabs.get_tab_title(_tabs.current_tab) if _drawer_open else "",
		"drawer_open": _drawer_open, "selected_crew": _selected_crew(),
		"selected_site": _selected(_sites), "selected_task": _selected(_tasks),
		"catalog_selected": _selected(_catalog_menu), "storage_id": storage_id,
		"storage_cost": _catalog.get(storage_id, {}).get("build_cost", {}),
		"storage_effect": _storage_effect(storage_id),
		"placement": _world_placement, "forecast_ok": _eva_forecast_ok,
		"forecast_reason": _eva_forecast_reason, "sim_failed": _sim_failed,
		"names": names, "catalog_names": catalog_names, "commander": _commander_name}

func _storage_effect(definition_id: String) -> String:
	## Describe what the storage module adds, read from its definition (never assumed).
	var parts: Array[String] = []
	var capacity: Dictionary = _catalog.get(definition_id, {}).get("storage_capacity", {})
	for id in _keys(capacity):
		var unit: String = _state.get("resources", {}).get(id, {}).get("unit", "")
		parts.append("%s more %s of %s storage" % [_short_number(float(capacity[id])), unit, _resource_name(id).to_lower()])
	return "it gives the colony " + " and ".join(parts) if not parts.is_empty() else "more storage capacity"

static func _short_number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value

func _tour_refresh() -> void:
	if _tour_card == null or _state.is_empty() or _tabs == null:
		return
	if _tour_reset:
		# A colony (re)started: remember what it began with and start paused, as taught.
		_tour_reset = false
		_tour.set_baseline(_state)
		_recommended_for = ""
		if _tour_enabled and _tour.active and int(_state.clock.time_scale) != 0:
			_time(0)
	if not _tour_enabled:
		_tour_step = {}
		_refresh_guide()
		_tour_card.visible = false
		_tour_overlay.visible = false
		return
	if _tabs.get_tab_title(_tabs.current_tab) == "Systems" and _drawer_open:
		_tour.mark_systems_seen()
	_tour_step = _tour.evaluate(_tour_ctx())
	_refresh_guide()
	if _tour_step.is_empty():
		_tour_card.visible = false
		_tour_overlay.visible = false
		return
	if _tour_step.id != _tour_step_id:
		_tour_step_id = _tour_step.id
		_tour_more.set_pressed_no_signal(false)
		_scroll_target_into_view.call_deferred()
	var step := _tour_step
	_tour_card.visible = true
	_tour_overlay.visible = true
	_tour_progress.text = step.phase_title if step.get("phase") == "independent" else "%s · step %d of %d" % [step.phase_title, step.index + 1, step.total]
	var flashing: bool = Time.get_ticks_msec() < _tour.flash_until_ms
	_tour_flash.text = _tour.flash if flashing else ""
	_tour_flash.visible = false # Keep acknowledgement out of the action card; progress records it.
	_tour_title.text = step.title
	_tour_body.text = step.body
	_tour_more.visible = not step.centered
	var explanation: bool = step.centered or step.id in ["orient", "ref_read"] or _tour_more.button_pressed
	_tour_body.visible = explanation
	var recovery: String = step.recovery
	if recovery.is_empty() and _tour_failure.get("step", "") == step.id:
		recovery = "That did not work: %s" % _tour_failure.text
	if recovery.is_empty() and _target_hidden_in_drawer(step.target):
		recovery = "Mission control is hidden. Click « at the top right to show it."
	_tour_recovery.text = recovery
	_tour_recovery.visible = not recovery.is_empty()
	_tour_action.text = step.action
	_tour_why.text = ("Why: " + step.why) if not str(step.why).is_empty() else ""
	_tour_why.visible = explanation and _tour_more.button_pressed and not _tour_why.text.is_empty()
	for child in _tour_buttons.get_children():
		child.queue_free()
	_tour_primary = null
	for spec in step.buttons:
		var button := _button(_tour_buttons, spec.label, _tour_button.bind(str(spec.id)))
		button.disabled = bool(spec.get("disabled", false))
		if spec.id == "skip":
			button.flat = true
			button.add_theme_color_override("font_color", DIM)
		elif _tour_primary == null and not str(spec.id).begins_with("add_crew:"):
			# The one prominent action: filled amber, larger text.
			_tour_primary = button
			button.add_theme_font_size_override("font_size", 19)
			button.add_theme_color_override("font_color", Color("#1a1308"))
			button.add_theme_stylebox_override("normal", _box(AMBER, 6, 18, 9, AMBER))
			button.add_theme_stylebox_override("hover", _box(AMBER.lightened(0.15), 6, 18, 9, AMBER))
		else:
			button.add_theme_stylebox_override("normal", _box(Color(AMBER, 0.2), 4, 12, 6, AMBER))
	_tour_skip.visible = not step.centered and step.get("phase") != "independent"
	_place_tour_card()

func _place_tour_card() -> void:
	## Width is fixed; height follows content through grow directions, so autowrapped text
	## never collapses the card to its narrowest word.
	var step := _tour_step
	var width := size.x if size.x > 0 else 1280.0
	var card_w := 0.0
	if step.centered:
		card_w = minf(560.0, width - 80.0)
		_tour_card.set_anchors_preset(Control.PRESET_CENTER)
		_tour_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_tour_card.grow_vertical = Control.GROW_DIRECTION_BOTH
		_tour_card.offset_left = -card_w * 0.5
		_tour_card.offset_right = card_w * 0.5
		_tour_card.offset_top = 0
		_tour_card.offset_bottom = 0
	else:
		var left := 8.0 + CREW_WIDTH + 12.0
		var right := width - 8.0 - (_drawer.size.x if _drawer.visible else 0.0) - 12.0
		var points: Array = _tour_targets().points
		# Steps that point into the world use a wide, short card so the target stays clear.
		var world_step := not points.is_empty()
		card_w = clampf(right - left, 300.0, 460.0)
		_tour_why.visible = _tour_why.visible and not world_step
		# Bottom of the world area by default; at the top when the target is in the lower half.
		var at_top := false
		var middle := (8.0 + TOP_HEIGHT + (size.y if size.y > 0 else 720.0)) * 0.5
		for point in points:
			if point.at.y > middle:
				at_top = true
		_tour_card.anchor_left = 0.0
		_tour_card.anchor_right = 0.0
		_tour_card.anchor_top = 0.0 if at_top else 1.0
		_tour_card.anchor_bottom = _tour_card.anchor_top
		_tour_card.grow_vertical = Control.GROW_DIRECTION_END if at_top else Control.GROW_DIRECTION_BEGIN
		_tour_card.offset_left = left
		_tour_card.offset_right = left + card_w
		_tour_card.offset_top = 8.0 + TOP_HEIGHT + 8.0 if at_top else -56.0
		_tour_card.offset_bottom = _tour_card.offset_top
	_tour_card.custom_minimum_size = Vector2(card_w, 0)
	move_child(_tour_card, get_child_count() - 1)
	move_child(_tour_overlay, get_child_count() - 1)

func _tour_button(id: String) -> void:
	if id == "skip":
		_tour.skip()
		_status.text = "Tutorial hidden. Resume or restart it from the Guide tab."
	elif id.begins_with("add_crew:"):
		var crew_id := id.get_slice(":", 1)
		for i in _crew.item_count:
			if _crew.get_item_metadata(i) == crew_id:
				_crew.select(i, false)
		_refresh_selection()
	elif id == "go_reference" or id == "restart_reference":
		reference_requested.emit()
	elif id == "restart_training":
		training_requested.emit()
	else:
		_tour.acknowledge(id)
	_tour_refresh()

func _scroll_target_into_view() -> void:
	var control := _tour_control(str(_tour_step.get("target", {}).get("id", ""))) if _tour_step.get("target", {}).get("kind") == "control" else null
	if control == null or not control.is_visible_in_tree():
		return
	var parent := control.get_parent()
	while parent != null and not parent is ScrollContainer:
		parent = parent.get_parent()
	if parent is ScrollContainer:
		parent.ensure_control_visible(control)

func _target_hidden_in_drawer(target: Dictionary) -> bool:
	return not _drawer_open and target.get("kind") in ["tab", "control"] and target.get("id") != "oxygen_info_hidden"

func _tour_control(id: String) -> Control:
	match id:
		"eva_summary": return _eva_summary
		"launch": return _launch
		"catalog": return _catalog_menu
		"place_on_map": return _place_on_map
		"tasks": return _tasks
		"suggest": return _suggest_button
		"assign": return _assign_button
		"oxygen_info": return _oxygen_info
		"trip_text": return _trip_text
	return null

func _tour_targets() -> Dictionary:
	## Screen rects/points for the current step's target, in HUD coordinates.
	var result := {"rects": [], "points": []}
	if _tour_step.is_empty():
		return result
	var target: Dictionary = _tour_step.get("target", {})
	result.context = []
	if _tour_primary != null and is_instance_valid(_tour_primary) and _tour_primary.is_visible_in_tree():
		# This step waits for the card's own button: point only at it, keep the subject as context.
		result.rects.append(_tour_primary.get_global_rect())
		var context := {"rects": [], "points": []}
		if target.get("kind") == "world" or target.has("world"):
			_add_world_target(context, target if target.get("kind") == "world" else target.world)
		elif target.get("kind") == "control":
			var control := _tour_control(str(target.id))
			if control != null and control.is_visible_in_tree():
				context.rects.append(_visible_rect(control))
		result.context = context.points + context.rects
		return result
	if _target_hidden_in_drawer(target):
		result.rects.append(_drawer_toggle.get_global_rect())
		return result
	match str(target.get("kind", "")):
		"crew":
			for i in _crew.item_count:
				if _crew.get_item_metadata(i) == target.id:
					var r := _crew.get_item_rect(i)
					result.rects.append(Rect2(_crew.get_global_rect().position + r.position, r.size).intersection(_visible_rect(_crew)))
		"tab":
			var bar := _tabs.get_tab_bar()
			for i in _tabs.get_tab_count():
				if _tabs.get_tab_title(i) == target.id:
					var r := bar.get_tab_rect(i)
					result.rects.append(Rect2(bar.get_global_rect().position + r.position, r.size))
		"control":
			var control := _tour_control(str(target.id))
			if control != null and control.is_visible_in_tree():
				result.rects.append(_visible_rect(control))
		"speed":
			var button: Button = _speed_buttons.get(int(target.id))
			if button != null:
				result.rects.append(button.get_global_rect())
		"world":
			_add_world_target(result, target)
	var secondary: Dictionary = target.get("world", {})
	if not secondary.is_empty():
		_add_world_target(result, secondary)
	var extra := str(target.get("secondary", ""))
	if not extra.is_empty():
		var control := _tour_control(extra)
		if control != null and control.is_visible_in_tree():
			result.rects.append(_visible_rect(control))
	return result

func _visible_rect(control: Control) -> Rect2:
	var rect := control.get_global_rect()
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			rect = rect.intersection(parent.get_global_rect())
			break
		parent = parent.get_parent()
	return rect

func _add_world_target(result: Dictionary, target: Dictionary) -> void:
	var point: Variant = null
	var label := str(target.get("label", ""))
	match str(target.get("kind", "world")) + ":" + str(target.get("id", "")):
		"world:lander":
			point = _world_points.get("lander")
		"world:cell":
			var cell := _recommended_storage_cell()
			if not cell.is_empty():
				point = Vector3(cell[0] + 0.5, 0.1, cell[1] + 0.5)
		"world:trip":
			point = _trip_position()
		"world:storage":
			point = _storage_position()
		"world:building":
			point = _building_position(str(target.get("building", "")))
	if str(target.get("kind")) == "site":
		var site: Dictionary = _state.get("sites", {}).get(str(target.get("id", "")), {})
		if not site.is_empty():
			point = Vector3(site.cell[0] + 0.5, 0.6, site.cell[1] + 0.5)
			label = "Salvage cache"
	elif str(target.get("kind")) == "building":
		point = _building_position(str(target.get("id", "")))
		label = "Damaged module"
	if point == null or not _world_projector.is_valid():
		return
	var screen: Variant = _world_projector.call(point)
	if screen == null:
		return
	result.points.append({"at": get_global_transform().affine_inverse() * (screen as Vector2), "label": label})

func _building_position(id: String) -> Variant:
	var b: Dictionary = _state.get("buildings", {}).get(id, {})
	if b.is_empty() or _world == null:
		return null
	var cells: Array = _world.building_cells(b).occupied_cells
	var total := Vector3.ZERO
	for cell in cells:
		total += Vector3(cell[0] + 0.5, 0.0, cell[1] + 0.5)
	return total / maxf(1.0, cells.size()) + Vector3(0, 0.8, 0)

func _storage_position() -> Variant:
	var storage_id: String = _tour_ctx().storage_id
	var newest := ""
	for id in _keys(_state.get("buildings", {})):
		if _state.buildings[id].definition_id == storage_id:
			newest = id
	return _building_position(newest) if not newest.is_empty() else null

func _trip_position() -> Variant:
	var trip: Dictionary = {}
	for id in _keys(_state.get("expeditions", {})):
		if _state.expeditions[id].status not in ["completed", "failed"]:
			trip = _state.expeditions[id]
	if trip.is_empty():
		return null
	var total := Vector3.ZERO
	for id in trip.crew_ids:
		var p: Array = _state.crew[id].position_m
		total += Vector3(p[0], p[1], p[2])
	return total / maxf(1.0, trip.crew_ids.size()) + Vector3(0, 1.0, 0)

func _recommended_storage_cell() -> Array:
	## A valid storage cell east of the habitat, nearest the airlock. Cached per revision.
	var storage_id: String = _tour_ctx().storage_id
	var key := "%s|%s|%s" % [_state.get("campaign_id", ""), _state.get("revision", -1), storage_id]
	if key == _recommended_for:
		return _recommended_cell
	_recommended_for = key
	_recommended_cell = []
	if _world == null or storage_id.is_empty() or not _world.has_method("validate_placement"):
		return _recommended_cell
	var airlock: Array = _world.map.base_airlock_cell
	for radius in range(2, 9):
		for dz in range(-radius, radius + 1):
			for dx in range(2, radius + 3):
				var cell := [int(airlock[0]) + dx, int(airlock[1]) + dz]
				var check: Dictionary = _world.validate_placement({"definition_id": storage_id, "cell": cell, "rotation_quarters": 0}, _state)
				if check.valid:
					_recommended_cell = cell
					return _recommended_cell
	return _recommended_cell

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
		result[id] = b.get("display_name", id) if is_catalog else "%s · #%s" % [
			_catalog.get(b.definition_id, {}).get("display_name", b.definition_id), _serial(id)]
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
		var record: Dictionary = records[id]
		if record.has("site_id"):
			result[id] = "Trip %s · %s" % [_serial(id), record.status.capitalize()]
		elif record.has("definition_id") and record.has("remaining_cargo"):
			result[id] = _humanize(str(record.definition_id))
		else:
			result[id] = "%s · %s" % [id, record.status.capitalize()] if record.has("status") else id
	return result

static func _serial(id: String) -> String:
	## "expedition_000002" -> "2": readable numbering instead of developer IDs.
	var digits := id.get_slice("_", id.get_slice_count("_") - 1)
	return str(int(digits)) if digits.is_valid_int() else id

static func _humanize(definition_id: String) -> String:
	return definition_id.trim_prefix("fixture_").replace("_", " ").capitalize()

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
	t.set_font_size("font_size", "TabContainer", 14)
	t.set_font_size("font_size", "TabBar", 14)
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
	var box := _box(color, 4, 8, 5)
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
