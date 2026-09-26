class_name FileBackend
extends MemoryBackend
## JSON persistence of the dedicated server (M2 stand-in for SqliteBackend, ARQ v2 §15): the whole store is one
## document written atomically (`.tmp` + rename) on `flush()`; `backup()` copies it. Loads the M1 save format too
## (players + world clock only).

var path: String = ""


func open(p_path: String) -> Error:
	path = p_path
	if not FileAccess.file_exists(path):
		return OK
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_warning("FileBackend: %s is not a JSON object (%s); starting empty" % [path, json.get_error_message()])
		return ERR_FILE_CORRUPT
	from_document(json.data)
	return OK


func flush() -> Error:
	if path == "":
		return ERR_UNCONFIGURED
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("FileBackend: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_document(), "  "))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if err != OK:
		push_warning("FileBackend: rename %s -> %s failed (%s)" % [tmp, path, error_string(err)])
	return err


func backup(to_path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_DOES_NOT_EXIST
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(to_path))


func close() -> void:
	flush()
