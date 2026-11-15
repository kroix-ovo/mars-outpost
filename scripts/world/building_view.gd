class_name BuildingView
extends Node3D
## Renders snapshot `buildings` records. Scenes are instantiated from each definition's
## scene_path when it exists; otherwise a procedural placeholder is built from the footprint and
## the definition's metadata.visual hints. Lifecycle, enabled, condition, power and blocking codes
## drive tints and a status light. This node only reads snapshots; it never writes state.

const BuildingNodeScript := preload("res://scripts/world/building_node.gd")

signal building_clicked(building_id: String)

var world_service: RefCounted
var terrain: Node3D
var _nodes: Dictionary = {}  # building_id -> Node3D
var _snapshot_buildings: Dictionary = {}


func setup(service: RefCounted, terrain_view: Node3D) -> void:
    world_service = service
    terrain = terrain_view


func reset() -> void:
    for node in _nodes.values():
        node.queue_free()
    _nodes.clear()
    _snapshot_buildings = {}


func apply_snapshot(snapshot: Dictionary) -> void:
    var records: Dictionary = snapshot.get("buildings", {})
    _snapshot_buildings = records
    var ids: Array = records.keys()
    ids.sort()
    for building_id in _nodes.keys():
        if not records.has(building_id):
            _nodes[building_id].queue_free()
            _nodes.erase(building_id)
    for building_id in ids:
        var record: Dictionary = records[building_id]
        var node: Node3D = _nodes.get(building_id)
        if node == null or node.definition_id != record.definition_id:
            if node != null:
                node.queue_free()
            node = _spawn(record)
            _nodes[building_id] = node
        node.apply_record(record, world_service.building_cells(record))


func building_at_cell(cell: Array) -> String:
    ## Returns the id of the non-destroyed building whose footprint covers the cell, or "".
    var key: String = "%d,%d" % [int(cell[0]), int(cell[1])]
    var ids: Array = _snapshot_buildings.keys()
    ids.sort()
    for building_id in ids:
        var record: Dictionary = _snapshot_buildings[building_id]
        if record.get("lifecycle") == "destroyed":
            continue
        for occupied in world_service.building_cells(record).occupied_cells:
            if "%d,%d" % [int(occupied[0]), int(occupied[1])] == key:
                return building_id
    return ""


func node_for(building_id: String) -> Node3D:
    return _nodes.get(building_id)


func _spawn(record: Dictionary) -> Node3D:
    var definition: Dictionary = world_service.definitions.get_definition(record.definition_id)
    var node: Node3D = null
    var scene_path: Variant = definition.get("scene_path")
    if scene_path is String and ResourceLoader.exists(scene_path):
        var packed: PackedScene = load(scene_path)
        var instance := packed.instantiate()
        if instance is Node3D and instance.has_method("apply_record"):
            node = instance
        elif instance is Node3D:
            # Wrap a plain scene so the shared status logic still applies.
            node = Node3D.new()
            node.set_script(BuildingNodeScript)
            node.add_child(instance)
        else:
            instance.queue_free()
    if node == null:
        node = Node3D.new()
        node.set_script(BuildingNodeScript)
    node.name = record.id
    node.definition_id = record.definition_id
    node.definition = definition
    node.ground_height = terrain.surface_height(float(record.cell[0]) + 0.5, float(record.cell[1]) + 0.5) if terrain != null else 0.0
    add_child(node)
    return node
