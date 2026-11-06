extends Resource
class_name EnszArchive

const ARCHIVE_EXTENSION := "ensz"
const LEVELS_ROOT := "user://levels"
const ALLOWED_EXTENSIONS: Array[String] = [
	"enso",
	"ogv",
	"opus",
	"png",
	"jpg",
	"jpeg",
	"webp",
	"mp3", # NOTE Temporary until we implement auto convert any music file to opus
	"import",
	"uid",
]
const JUNK_NAMES: Array[String] = [".ds_store", "thumbs.db", "desktop.ini"]


func load(path: String, dest_root: String = LEVELS_ROOT) -> Dictionary:
	var archive_path := path.strip_edges()
	if not _check_path_exists(archive_path):
		return _error_result("File not found.")
	var reader := ZIPReader.new()
	var valid := _check_file_valid(archive_path, reader)
	if not bool(valid.get("valid", false)):
		return _error_result(str(valid.get("reason", "Invalid .ensz archive.")))
	var levels := _extract_archive_levels(archive_path, reader, dest_root)
	if levels.is_empty():
		return _error_result("Failed to extract any level folders.")
	return { "error": false, "reason": "", "levels": levels }


func find_existing_levels(path: String, dest_root: String = LEVELS_ROOT) -> Array[String]:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return [] as Array[String]
	var files_by_level := _group_files_by_level(reader.get_files())
	reader.close()

	var existing: Array[String] = []
	for level_name in _valid_level_names(files_by_level):
		var safe_name := _sanitize_folder_name(level_name)
		if DirAccess.dir_exists_absolute(dest_root.path_join(safe_name)):
			existing.append(safe_name)
	return existing


func _check_path_exists(path: String) -> bool:
	if path.is_empty():
		return false
	return FileAccess.file_exists(path)


func _check_file_valid(path: String, reader: ZIPReader) -> Dictionary:
	# step 1 is ext correct
	if path.get_extension().to_lower() != ARCHIVE_EXTENSION:
		return _invalid("Invalid file type. Expected a .ensz archive.")
	if reader.open(path) != OK:
		return _invalid("Not a valid .ensz archive (could not open it as ZIP).")

	# step 2 is it empty
	var entries := reader.get_files()
	if entries.is_empty():
		reader.close()
		return _invalid("Archive is empty.")

	var scan := _scan_entries(entries)
	reader.close()
	if not str(scan["error"]).is_empty():
		return _invalid(str(scan["error"]))

	# step 3 and 4 are checked while scanning / validating the layout
	return _validate_layout(scan)


func _scan_entries(entries: PackedStringArray) -> Dictionary:
	var scan := _new_scan()
	for raw in entries:
		var entry := _normalize_entry(raw)
		if entry.is_empty() or _is_junk_entry(entry):
			continue
		var error := _scan_entry(entry, scan)
		if not error.is_empty():
			scan["error"] = error
			return scan
	return scan


func _new_scan() -> Dictionary:
	return {
		"error": "",
		"root_files": [] as Array[String],
		"level_names": [] as Array[String],
		"level_has_enso": { },
		"file_count": 0,
	}


func _scan_entry(entry: String, scan: Dictionary) -> String:
	if not _is_safe_relative_path(entry):
		return "Archive contains an unsafe path: " + entry
	if entry.ends_with("/"):
		_register_level(scan, _top_level_dir(entry))
		return ""

	scan["file_count"] = int(scan["file_count"]) + 1
	var parts := entry.split("/", false)
	if parts.size() < 2:
		(scan["root_files"] as Array[String]).append(entry)
		return ""

	# step 4 is it only contains whitelisted extension
	if not _is_allowed_extension(entry):
		return "Unsupported file in level folder: " + entry

	var top := str(parts[0])
	_register_level(scan, top)
	if _is_root_enso(parts):
		(scan["level_has_enso"] as Dictionary)[top] = true
	return ""


func _register_level(scan: Dictionary, level_name: String) -> void:
	if level_name.is_empty():
		return
	var level_has_enso := scan["level_has_enso"] as Dictionary
	if level_has_enso.has(level_name):
		return
	level_has_enso[level_name] = false
	(scan["level_names"] as Array[String]).append(level_name)


func _validate_layout(scan: Dictionary) -> Dictionary:
	var root_files := scan["root_files"] as Array[String]
	if not root_files.is_empty():
		return _invalid(
			"Archive has file(s) at the root: %s. .ensz archives must contain level folders."
			% ", ".join(root_files)
		)

	var missing_chart := _levels_missing_chart(scan)
	if not missing_chart.is_empty():
		return _invalid(
			"Level folder(s) missing a .enso file at their root: %s." % ", ".join(missing_chart)
		)

	var level_names := scan["level_names"] as Array[String]
	if level_names.is_empty():
		return _invalid("No level folder containing .enso files was found.")
	return { "valid": true, "reason": "" }


func _levels_missing_chart(scan: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	var level_has_enso := scan["level_has_enso"] as Dictionary
	var level_names := scan["level_names"] as Array[String]
	for level_name in level_names:
		if not bool(level_has_enso.get(level_name, false)):
			missing.append(level_name)
	return missing


func _extract_archive_levels(path: String, reader: ZIPReader, dest_root: String) -> Array[String]:
	if reader.open(path) != OK:
		return [] as Array[String]
	var files_by_level := _group_files_by_level(reader.get_files())
	var level_names := _valid_level_names(files_by_level)
	var extracted := _extract_levels(reader, files_by_level, level_names, dest_root)
	reader.close()
	return extracted


func _group_files_by_level(entries: PackedStringArray) -> Dictionary:
	var files_by_level: Dictionary = { }
	for raw in entries:
		var entry := _normalize_entry(raw)
		if not _is_archive_file(entry):
			continue
		var level_name := _level_name_of(entry)
		if level_name.is_empty():
			continue
		if not files_by_level.has(level_name):
			files_by_level[level_name] = []
		(files_by_level[level_name] as Array).append(raw)
	return files_by_level


func _valid_level_names(files_by_level: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for level_name in files_by_level.keys():
		if _has_root_enso(files_by_level[level_name]):
			names.append(str(level_name))
	names.sort()
	return names


func _extract_levels(
	reader: ZIPReader,
	files_by_level: Dictionary,
	level_names: Array[String],
	dest_root: String,
) -> Array[String]:
	var extracted: Array[String] = []
	DirAccess.make_dir_recursive_absolute(dest_root)
	for level_name in level_names:
		var level_dir := _extract_level_folder(
			reader,
			level_name,
			files_by_level[level_name],
			dest_root,
		)
		if not level_dir.is_empty():
			extracted.append(level_dir)
	return extracted


func _extract_level_folder(
	reader: ZIPReader,
	level_name: String,
	entries: Array,
	dest_root: String,
) -> String:
	var level_dir := _level_dir(level_name, dest_root)
	if DirAccess.dir_exists_absolute(level_dir):
		_remove_dir(level_dir)
	if DirAccess.make_dir_recursive_absolute(level_dir) != OK:
		push_error("EnszArchive: failed to create level folder: " + level_dir)
		return ""

	var written := 0
	for raw in entries:
		if _extract_file(reader, str(raw), level_dir):
			written += 1
	return level_dir if written > 0 else ""


func _extract_file(reader: ZIPReader, raw: String, level_dir: String) -> bool:
	var relative := _relative_entry_path(raw)
	if relative.is_empty():
		return false

	var dst := level_dir.path_join(relative)
	var parent := dst.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(parent) != OK:
		push_error("EnszArchive: failed to create directory: " + parent)
		return false

	var file := FileAccess.open(dst, FileAccess.WRITE)
	if file == null:
		push_error("EnszArchive: failed to write: " + dst)
		return false
	file.store_buffer(reader.read_file(raw))
	file.close()
	return true


func _is_archive_file(entry: String) -> bool:
	if entry.is_empty() or entry.ends_with("/"):
		return false
	if _is_junk_entry(entry):
		return false
	if not _is_safe_relative_path(entry):
		return false
	return not _level_name_of(entry).is_empty()


func _has_root_enso(entries: Array) -> bool:
	for raw in entries:
		var parts := _normalize_entry(str(raw)).split("/", false)
		if _is_root_enso(parts):
			return true
	return false


func _is_root_enso(parts: PackedStringArray) -> bool:
	return parts.size() == 2 and parts[1].get_extension().to_lower() == "enso"


func _level_name_of(entry: String) -> String:
	var parts := entry.split("/", false)
	if parts.size() < 2:
		return ""
	return str(parts[0])


func _top_level_dir(entry: String) -> String:
	var parts := entry.trim_suffix("/").split("/", false)
	if parts.is_empty():
		return ""
	return str(parts[0])


func _relative_entry_path(raw: String) -> String:
	var parts := _normalize_entry(raw).split("/", false)
	if parts.size() < 2:
		return ""
	return "/".join(parts.slice(1))


func _normalize_entry(raw: String) -> String:
	var entry := raw.replace("\\", "/").strip_edges()
	while entry.begins_with("./"):
		entry = entry.substr(2)
	return entry


func _is_safe_relative_path(entry: String) -> bool:
	if entry.is_empty() or entry.begins_with("/"):
		return false
	var parts := entry.split("/", false)
	if parts.is_empty():
		return false
	for part in parts:
		if part == "." or part == ".." or part.contains(":"):
			return false
	return true


func _is_junk_entry(entry: String) -> bool:
	for part in entry.split("/", false):
		if part == "__MACOSX" or part.begins_with("._"):
			return true
		if JUNK_NAMES.has(part.to_lower()):
			return true
	return false


func _is_allowed_extension(entry: String) -> bool:
	return ALLOWED_EXTENSIONS.has(entry.get_extension().to_lower())


func _level_dir(level_name: String, dest_root: String = LEVELS_ROOT) -> String:
	return dest_root.path_join(_sanitize_folder_name(level_name))


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir():
			_remove_dir(path.path_join(entry))
		else:
			dir.remove(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _sanitize_folder_name(raw: String) -> String:
	var bad := ["/", "\\", ":", "*", "?", '"', "<", ">", "|"]
	var out := raw.strip_edges()
	for ch in bad:
		out = out.replace(ch, "_")
	out = out.strip_edges().rstrip(".")
	if out.is_empty():
		out = "level"
	return out


func _invalid(reason: String) -> Dictionary:
	return { "valid": false, "reason": reason }


func _error_result(reason: String) -> Dictionary:
	return { "error": true, "reason": reason, "levels": [] as Array[String] }
