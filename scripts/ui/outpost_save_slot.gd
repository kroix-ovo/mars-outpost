extends RefCounted

static func save(facade: RefCounted, path: String) -> Dictionary:
	var record: Dictionary = facade.export_save()
	if record.get("ok") == false:
		return record
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return failure("Could not open a temporary save file.")
	file.store_string(JSON.stringify(record, "", true, true))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return failure("Could not write the save. The previous save was kept.")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),
			ProjectSettings.globalize_path(path)) != OK:
		return failure("Could not replace the save. The previous save was kept.")
	return {"ok": true, "reason": ""}

static func load_slot(facade: RefCounted, path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return failure("No save in this slot.")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return failure("The save file is not readable.")
	return facade.import_save(parsed)

static func failure(reason: String) -> Dictionary:
	return {"ok": false, "code": "invalid_save", "reason": reason}
