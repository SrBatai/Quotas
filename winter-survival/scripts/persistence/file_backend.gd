class_name FileBackend
extends MemoryBackend
## JSON persistence of the dedicated server (ARQ v2 §15): the fallback when godot-sqlite cannot load (web build,
## unsupported platform, missing addon) and the M2 format. The whole store is one document written atomically
## (`.tmp` + fsync'd close + rename: a crash leaves the previous complete file) on `flush()`; `backup()` copies it.
## The document carries `schema_version` and walks the same numbered migrations as SQLite (PersistenceSchema);
## it also loads the M2 (no version) and M1 (players + world clock only) formats.

var path: String = ""
var _schema_loaded: int = PersistenceSchema.VERSION


func kind() -> String:
	return "file"


func open(p_path: String) -> Error:
	path = p_path
	var doc: Dictionary = {}   # a new store goes through the migrations too (world_meta gets world_version like SQLite)
	if FileAccess.file_exists(path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
			last_error = "%s is not a JSON object (%s)" % [path, json.get_error_message()]
			push_warning("FileBackend: %s; starting empty" % last_error)
			return ERR_FILE_CORRUPT
		doc = json.data
	var v := int(doc.get("schema_version", 0))
	if v > PersistenceSchema.VERSION:
		last_error = "%s has schema %d, newer than this server (%d)" % [path, v, PersistenceSchema.VERSION]
		push_warning("FileBackend: " + last_error)
		return ERR_FILE_UNRECOGNIZED
	_schema_loaded = v
	for m in PersistenceSchema.migrations_after(v):
		m.call("document", doc)
	doc["schema_version"] = PersistenceSchema.VERSION
	from_document(doc)
	return OK


## Schema version the file had before open() migrated it (tests).
func loaded_schema() -> int:
	return _schema_loaded


func flush() -> Error:
	if path == "":
		return ERR_UNCONFIGURED
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())]
		push_warning("FileBackend: " + last_error)
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_document(), "  "))
	f.flush()
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		last_error = "rename %s -> %s failed (%s)" % [tmp, path, error_string(err)]
		push_warning("FileBackend: " + last_error)
	return err


func backup(to_path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_DOES_NOT_EXIST
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(to_path))


func close() -> void:
	flush()
