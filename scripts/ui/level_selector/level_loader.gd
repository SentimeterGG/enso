class_name LevelLoader
extends RefCounted

const GAME_SCENE_PATH := "res://scenes/gameplay/game.tscn"

static func load_chart(chart_path: String) -> ChartData:
	if chart_path.is_empty():
		push_error("LevelLoader: empty chart path.")
		return ChartData.new()
	var chart := ChartParser.load(chart_path)
	if chart.is_empty():
		push_warning("LevelLoader: chart parsed empty: " + chart_path)
		return chart
	Global.current_chart = chart
	return chart


static func load_by_index(level_list: Node, index: int) -> ChartData:
	var levels: Array = level_list.get("levels")
	if levels.is_empty():
		push_error("LevelLoader: level list is empty.")
		return ChartData.new()
	if index < 0 or index >= levels.size():
		push_error("LevelLoader: index %d out of range (0..%d)." % [index, levels.size() - 1])
		return ChartData.new()
	var entry: Dictionary = levels[index]
	var chart_paths: Array = entry.get("chart_paths", [])
	var path := str(chart_paths[0]) if not chart_paths.is_empty() else str(entry.get("chart_path", ""))
	return load_chart(path)


static func load_selected(level_list: Node) -> ChartData:
	if level_list.has_method("get_selected_chart_path"):
		var path := str(level_list.call("get_selected_chart_path"))
		if not path.is_empty():
			return load_chart(path)
	if level_list.has_method("get_selected_level_index"):
		return load_by_index(level_list, int(level_list.call("get_selected_level_index")))
	return load_by_index(level_list, int(level_list.get("selected_index")))
