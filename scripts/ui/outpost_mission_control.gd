extends Control
## World-owned scene wiring can mount one panel and feed it the active campaign.
## The facade still owns gameplay, and the world still owns input and its clock.

const CrewView = preload("res://scenes/crew/crew_view.tscn")

@onready var hud: PanelContainer = $Dock/HUD
@onready var _dock: VBoxContainer = $Dock
@onready var _toggle: Button = $Dock/Toggle

var _simulation: RefCounted
var _crew_view: Node3D

func _ready() -> void:
	resized.connect(_resize_dock)
	_toggle.pressed.connect(_toggle_hud)
	hud.campaign_loaded.connect(_snap_loaded_crew)
	_resize_dock()

func bind(crew_parent: Node3D, simulation: RefCounted, adapter: RefCounted,
		world_service: RefCounted, catalog: Dictionary,
		save_path: String = "user://outpost_quick_save.json") -> void:
	if _simulation != null:
		_simulation.disconnect("state_changed", _apply_snapshot)
	_simulation = simulation
	if not is_instance_valid(_crew_view):
		_crew_view = CrewView.instantiate()
		crew_parent.add_child(_crew_view)
		_crew_view.crew_selected.connect(hud.select_crew)
		hud.crew_selection_changed.connect(_crew_view.set_selected_crew)
	elif _crew_view.get_parent() != crew_parent:
		_crew_view.reparent(crew_parent, false)
	hud.bind(simulation, adapter, world_service, catalog, save_path)
	_simulation.connect("state_changed", _apply_snapshot)
	_crew_view.apply_snapshot(_simulation.get_snapshot(), true)

func _exit_tree() -> void:
	if _simulation != null:
		_simulation.disconnect("state_changed", _apply_snapshot)
		_simulation = null
	if is_instance_valid(_crew_view):
		_crew_view.queue_free()

func _apply_snapshot(snapshot: Dictionary) -> void:
	_crew_view.apply_snapshot(snapshot)

func _snap_loaded_crew(snapshot: Dictionary) -> void:
	_crew_view.apply_snapshot(snapshot, true)

func _resize_dock() -> void:
	_dock.offset_left = -minf(size.x, clampf(size.x * 0.52, 440.0, 680.0))

func _toggle_hud() -> void:
	hud.visible = not hud.visible
	_toggle.text = "Hide mission control" if hud.visible else "Show mission control"
