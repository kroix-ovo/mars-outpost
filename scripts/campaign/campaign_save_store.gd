extends RefCounted
## Native save storage. Browser host persistence must be verified before web release.
const MAX_BYTES := 32 * 1024 * 1024
const Codec = preload("res://scripts/campaign/campaign_save.gd")
var directory: String

func _init(save_directory: String = "user://campaign_saves") -> void:
	directory = save_directory

func write(sim: RefCounted, slot: String = "manual") -> Dictionary:
	if not valid_slot(slot): return fail("Invalid save slot.")
	var record: Dictionary = sim.export_save()
	if record.has("ok") and not record.ok: return record
	var validated := Codec.decode(record, sim._world_service, sim._crew_adapter != null, sim.boundary_kinds())
	if not validated.ok: return validated
	var text := JSON.stringify(record, "", true, true)
	if text.to_utf8_buffer().size() > MAX_BYTES: return fail("Save exceeds the supported size.")
	var root := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(root) != OK: return fail("Cannot create save directory.")
	var path := root.path_join(slot + ".json")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return fail("Cannot open temporary save.")
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_string(temporary) != text: return fail("Temporary save verification failed.")
	# Preserve the previous valid bytes before atomically replacing the primary.
	if valid_checkpoint(path, sim):
		if DirAccess.copy_absolute(path, path + ".bak.tmp") != OK: return fail("Cannot preserve previous save.")
		if DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak") != OK: return fail("Cannot replace save backup.")
	if DirAccess.rename_absolute(temporary, path) != OK: return fail("Cannot replace primary save; previous save retained.")
	return {"ok": true, "code": "ok", "reason": "", "path": path}

func valid_checkpoint(path: String, sim: RefCounted) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return false
	if file.get_length() > MAX_BYTES:
		file.close()
		return false
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary: return false
	return Codec.decode(parser.data, sim._world_service, sim._crew_adapter != null, sim.boundary_kinds()).ok

func read(sim: RefCounted, slot: String = "manual", recover_backup: bool = true) -> Dictionary:
	if not valid_slot(slot): return fail("Invalid save slot.")
	var path := ProjectSettings.globalize_path(directory).path_join(slot + ".json")
	var result := load_path(sim, path)
	if not result.ok and recover_backup:
		var recovered := load_path(sim, path + ".bak")
		if recovered.ok:
			recovered.recovered_backup = true
			return recovered
	return result

func autosave(sim: RefCounted) -> Dictionary:
	var root := ProjectSettings.globalize_path(directory)
	var slot := "auto_0"
	var oldest: int = 9223372036854775807
	for i in 3:
		var name := "auto_%d" % i
		var path := root.path_join(name + ".json")
		var modified: int = FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
		if modified < oldest:
			oldest = modified
			slot = name
	return write(sim, slot)

func load_path(sim: RefCounted, path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return fail("Save file not found.")
	if file.get_length() > MAX_BYTES:
		file.close()
		return fail("Save exceeds the supported size.")
	var parser := JSON.new()
	var error := parser.parse(file.get_as_text())
	file.close()
	if error != OK or not parser.data is Dictionary: return fail("Save is not a valid JSON object.")
	return sim.import_save(parser.data)

static func valid_slot(slot: String) -> bool:
	return slot in ["manual", "auto_0", "auto_1", "auto_2"]

static func fail(reason: String) -> Dictionary:
	return {"ok": false, "code": "save_io_error", "reason": reason}
