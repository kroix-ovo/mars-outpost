extends Node3D
## Optional world presentation. Instantiate one view under the world root.

const Avatar = preload("res://scenes/crew/crew_avatar.tscn")
signal crew_selected(crew_id: String)

var _avatars: Dictionary = {}
var _campaign := ""
var _revision := -1

func apply_snapshot(snapshot: Dictionary, force_snap: bool = false) -> void:
	if not snapshot.has("crew"):
		return
	var snap: bool = force_snap or snapshot.campaign_id != _campaign or snapshot.revision < _revision
	_campaign = snapshot.campaign_id
	_revision = snapshot.revision
	for id in _avatars.keys():
		if not snapshot.crew.has(id):
			_avatars[id].queue_free()
			_avatars.erase(id)
	var ids: Array = snapshot.crew.keys()
	ids.sort()
	for id in ids:
		if not _avatars.has(id):
			var avatar := Avatar.instantiate()
			add_child(avatar)
			avatar.selected.connect(func(crew_id: String): crew_selected.emit(crew_id))
			_avatars[id] = avatar
		_avatars[id].apply_record(snapshot.crew[id], snap)
	# Spawned crew share the airlock coordinate. Show one group label instead
	# of painting six names over one another; the roster still selects each one.
	var groups := {}
	for id in ids:
		var key: String = str(snapshot.crew[id].position_m)
		if not groups.has(key): groups[key] = []
		groups[key].append(id)
	for group in groups.values():
		for i in range(group.size()):
			var label: Label3D = _avatars[group[i]].get_node("Nameplate")
			label.visible = i == 0
			if group.size() > 1 and i == 0: label.text = "%d crew · %s" % [group.size(), snapshot.crew[group[i]].location_kind.capitalize()]
