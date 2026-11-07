class_name ChartImporter
extends RefCounted

## Loads a single-level .ensz archive and pushes its charts into the MAPPING editor.

const ARCHIVE_EXTENSION := "ensz"
const IMPORT_ROOT := "user://level_creator_import"

signal chart_imported(chart: ChartData)
signal toast_requested(
	title: String,
	message: String,
	kind: NotificationToast.Kind,
	duration: float,
)

var _mapping_group: Control
var _archive := EnszArchive.new()


func _init(mapping_group: Control) -> void:
	_mapping_group = mapping_group


func _toast(
	title: String,
	message: String,
	kind: NotificationToast.Kind,
	duration: float = -1.0,
) -> void:
	toast_requested.emit(title, message, kind, duration)


func import_archive(path: String) -> bool:
	if not _validate_archive_path(path):
		return false

	var loaded := _archive.load_single(path, IMPORT_ROOT)
	if bool(loaded.get("error", true)):
		var reason := str(loaded.get("reason", "Could not read the archive."))
		push_error(reason)
		_toast("Import Failed", reason, NotificationToast.Kind.WARN)
		return false

	var levels: Array = loaded.get("levels", [])
	if levels.size() != 1:
		push_error("Expected exactly one level folder in: " + path)
		_toast(
			"Import Failed",
			"The .ensz archive must contain exactly one level folder.",
			NotificationToast.Kind.WARN,
		)
		return false

	var chart_paths := _find_enso_files(str(levels[0]))
	if chart_paths.is_empty():
		push_error("No .enso files found in: " + str(levels[0]))
		_toast(
			"Difficulty Missing",
			"No .enso files found inside the archive.",
			NotificationToast.Kind.WARN,
		)
		return false
	chart_paths.sort() # stable, predictable difficulty order in the dropdown
	var result := _import_chart_files(chart_paths)
	_notify_folder_import_result(result["imported"], result["failed"])
	return true


func _validate_archive_path(path: String) -> bool:
	var archive_path := path.strip_edges()
	if (
		not archive_path.is_empty()
		and FileAccess.file_exists(archive_path)
		and archive_path.get_extension().to_lower() == ARCHIVE_EXTENSION
	):
		return true
	push_error("Invalid .ensz file: " + path)
	_toast(
		"Import Failed",
		"Choose a valid .ensz archive.",
		NotificationToast.Kind.WARN,
	)
	return false


func _import_chart_files(chart_paths: Array[String]) -> Dictionary:
	var metadata_applied := false
	var imported_names: Array[String] = []
	var failed_names: Array[String] = []
	for path in chart_paths:
		var diff_name := _import_chart_file(path, not metadata_applied)
		if diff_name.is_empty():
			failed_names.append(path.get_file())
			continue
		metadata_applied = true
		imported_names.append(diff_name)
	return { "imported": imported_names, "failed": failed_names }


func _import_chart_file(path: String, apply_metadata: bool) -> String:
	var chart := ChartParser.load(path)
	if chart.is_empty() or chart.metadata.is_empty():
		push_error("No metadata found in chart: " + path)
		return ""
	if apply_metadata:
		chart_imported.emit(chart)
	var diff_name := path.get_file().get_basename() # "hard.enso" -> "hard"
	if _mapping_group != null and _mapping_group.has_method("import_difficulty"):
		_mapping_group.import_difficulty(diff_name, chart)
	return diff_name


func _find_enso_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if not da.current_is_dir() and entry.get_extension().to_lower() == "enso":
			out.append(dir.path_join(entry))
		entry = da.get_next()
	da.list_dir_end()
	return out


func _notify_folder_import_result(imported: Array[String], failed: Array[String]) -> void:
	if imported.is_empty():
		_toast(
			"Import Failed",
			"No valid .enso files.",
			NotificationToast.Kind.WARN,
		)
		return
	var message := _folder_import_message(imported, failed)
	if failed.is_empty():
		_toast("Import Complete", message, NotificationToast.Kind.SUCCESS)
		return
	_toast(
		"Import Completed with Errors",
		message,
		NotificationToast.Kind.WARN,
		4.0,
	)


func _folder_import_message(imported: Array[String], failed: Array[String]) -> String:
	var suffix := "y" if imported.size() == 1 else "ies"
	var message := "Imported %d difficult%s: %s" % [imported.size(), suffix, ", ".join(imported)]
	if not failed.is_empty():
		message += " (%d failed: %s)" % [failed.size(), ", ".join(failed)]
	return message


func _notify_import_result(chart: ChartData, diff_name: String) -> void:
	var counts := _mapping_counts()
	var title := 'Imported "%s"' % diff_name
	if counts["solo"] > 0 or chart.is_incomplete():
		_toast(
			title,
			"%d beats, %d shapes. %d solo need setup."
			% [counts["beats"], counts["shapes"], counts["solo"]],
			NotificationToast.Kind.WARN,
			4.0,
		)
	else:
		_toast(
			title,
			"%d beats, %d shapes." % [counts["beats"], counts["shapes"]],
			NotificationToast.Kind.SUCCESS,
		)


func _mapping_counts() -> Dictionary:
	var counts := { "beats": 0, "shapes": 0, "solo": 0 }
	if _mapping_group == null:
		return counts
	if _mapping_group.has_method("get_beat_times_ms"):
		counts["beats"] = (_mapping_group.call("get_beat_times_ms") as Array).size()
	if _mapping_group.has_method("get_shapes"):
		counts["shapes"] = (_mapping_group.call("get_shapes") as Array).size()
	if _mapping_group.has_method("get_solo_beats_ms"):
		counts["solo"] = (_mapping_group.call("get_solo_beats_ms") as Array).size()
	else:
		counts["solo"] = maxi(0, counts["beats"] - counts["shapes"])
	return counts
