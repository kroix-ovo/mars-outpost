extends Control
## Standalone demonstration on a synthetic flat map, without a project main scene.

const Fixture = preload("res://tests/crew_ui/fixture_facade.gd")
var fixture := Fixture.new()

func _ready() -> void:
	var result := fixture.open()
	if not result.ok:
		push_error(result.reason)
		get_tree().quit(1)
		return
	var b: Dictionary = fixture.state.buildings.building_000003
	b.condition = 0.7
	fixture.add_job("repair", b.id, 8.0)
	# This existing fixture module stands in for a powered crop worksite in the demo.
	fixture.add_job("farm", "building_000004", 10.0)
	fixture.state.clock.time_scale = 0
	$HUD.bind(fixture, fixture.adapter, fixture.world, fixture.catalog, "user://crew_ui_harness_save.json")
	$HUD.set_placement_cell(Vector2i(4, 8))
	$CrewPreview/Viewport/CrewView.crew_selected.connect($HUD.select_crew)
	fixture.state_changed.connect($CrewPreview/Viewport/CrewView.apply_snapshot)
	$CrewPreview/Viewport/CrewView.apply_snapshot(fixture.get_snapshot())

func _process(delta: float) -> void:
	if not fixture.state.is_empty():
		fixture.advance(delta)
