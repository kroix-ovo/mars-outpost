extends SceneTree
## Optional integration check for a checkout containing Tasks 01, 02 and 03.
## Mounts the production scenes in the existing world, using its real service and facade.

const MissionControl = preload("res://scenes/ui/outpost_mission_control.tscn")
const Adapter = preload("res://scripts/crew/crew_adapter.gd")
const WorldScene := "res://scenes/world/main.tscn"
const SimulationScript := "res://scripts/simulation/simulation.gd"
const PAYLOAD := {
	"site_id": "site_cargo_a",
	"crew_ids": ["crew_000001"],
	"work_duration_s": 20.0,
	"oxygen_kg_per_crew": 0.12,
	"battery_kwh_per_crew": 0.006,
}

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not ResourceLoader.exists(WorldScene) or not ResourceLoader.exists(SimulationScript):
		print("CREW_WORLD_SKIP: Requires the Task 01 and Task 02 code.")
		quit(0)
		return
	var world: Node = load(WorldScene).instantiate()
	root.add_child(world)
	var bridge: Node = world.get_node("Integration")
	bridge.auto_advance = false
	if bridge.backend_kind != "simulation":
		_fail("Main world failed to boot on OutpostSimulation.")
		return
	var mount := MissionControl.instantiate()
	world.get_node("UIRoot").add_child(mount)
	world.site_selected.connect(func(id: String, _route: Dictionary): mount.hud.select_site(id))
	world.building_selected.connect(mount.hud.select_building)
	if not _bind(mount, world, bridge):
		return

	var hud: PanelContainer = mount.hud
	var simulation: RefCounted = bridge._backend
	var initial: Dictionary = simulation.get_snapshot()
	_check(hud._crew.item_count == initial.crew.size(), "Roster matches the authoritative snapshot.")
	var view: Node3D = world.get_node("CrewRoot").get_child(0)
	_check(view.get_child_count() == initial.crew.size(), "Each astronaut has a world avatar.")
	await process_frame
	await process_frame
	var panel_rect := hud.get_global_rect()
	_check(mount.mouse_filter == Control.MOUSE_FILTER_IGNORE and panel_rect.position.x > 0.0
		and panel_rect.end.x <= mount.size.x + 1.0,
		"The dock stays on screen and leaves space for map input.")

	world._select_at(initial.sites.site_cargo_a.cell)
	_check(hud._selected(hud._sites) == "site_cargo_a" and hud._tabs.current_tab == hud.Tab.EVA,
		"Site picking in the actual world opens the EVA panel.")
	view.crew_selected.emit("crew_000001")
	_check(hud._selected_crew() == ["crew_000001"] and not hud._launch.disabled,
		"Real WorldService provides a valid route for the shared synthetic salvage plan.")
	hud._oxygen.value = 0.01
	_check(hud._launch.disabled and "Load at least" in hud._eva_forecast.text,
		"Live plan shows which suit reserve blocks launch.")
	hud._oxygen.value = PAYLOAD.oxygen_kg_per_crew

	hud._time(0)
	simulation.process_pending_commands()
	_check(simulation.get_snapshot().clock.time_scale == 0 and "Paused" in hud._vitals.text,
		"HUD command pauses the real simulation.")
	for id in ["building_000001", "building_000002"]:
		world._select_at(initial.buildings[id].cell)
		_check(hud._selected(hud._buildings) == id and hud._tabs.current_tab == hud.Tab.BUILD,
			"World selects the intended module in the HUD.")
		if initial.buildings[id].enabled:
			hud._toggle_building.pressed.emit()
			simulation.process_pending_commands()
	_check("stale" in hud._resources.text, "While paused the HUD flags last-tick rates after module toggles.")

	hud._time(1)
	simulation.step(1.0)
	var live: Dictionary = simulation.get_snapshot()
	var oxygen: Dictionary = live.resources.oxygen_kg
	_check(oxygen.net_rate_per_s < 0.0 and "%+.6f kg/s" % oxygen.net_rate_per_s in hud._resources.text
		and "stale" not in hud._resources.text, "After power loss the HUD displays the real oxygen rate.")
	_check("No power reaching this module" in hud._oxygen_info.text,
		"Oxygen explanation names the upstream power problem.")
	_check("No active alerts" != hud._alerts.text, "The HUD presents authoritative shortage alerts.")

	var switched: Dictionary = world.load_world(1)
	if not switched.ok:
		_fail("Authored world failed to boot: " + switched.reason)
		return
	bridge.auto_advance = false
	if not _bind(mount, world, bridge):
		return
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bridge.simulation_config_path))
	var science: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.science_config_path))
	if not science.crew_metabolism.get("eva_supported", true):
		hud.select_crew("crew_000001")
		_check(hud._launch.disabled and "not configured" in hud._eva_forecast.text,
			"The HUD communicates that EVA workload rates are unavailable for this scenario.")
	_check(world.get_node("CrewRoot").get_child_count() == 1, "Switching worlds reuses the mount.")
	print("CREW_WORLD_%s checks=%d" % ["PASS" if _failures == 0 else "FAIL", _checks])
	quit(0 if _failures == 0 else 1)

func _bind(mount: Node, world: Node, bridge: Node) -> bool:
	var simulation: RefCounted = bridge._backend
	var adapter := Adapter.new(bridge.world_service)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(bridge.simulation_config_path))
	var result := adapter.initialize(config, simulation.get_snapshot())
	if not result.ok:
		_fail("Crew adapter setup failed: " + result.reason)
		return false
	var catalog := {}
	for id in bridge.definitions.ids():
		catalog[id] = bridge.definitions.get_definition(id)
	mount.bind(world.get_node("CrewRoot"), simulation, adapter, bridge.world_service, catalog)
	return true

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
