# level_loader.gd — Bridges the level selector and the game scene: takes the
# selected entry from a level list (index or chart path), parses it with
# ChartParser, and stashes the result in Global.current_chart so game.tscn
# can start instantly without reparsing.
# RETURN: ChartData stored in Global.current_chart (fresh empty ChartData on failure)
class_name LevelLoader
extends RefCounted

const GAME_SCENE_PATH := "res://scenes/game.tscn"


## Parse chart_path and publish it as Global.current_chart.
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


## Load levels[index].chart_path from a level list node (duck-typed so the
## list script needs no class_name — it just needs `levels` and each entry
## needs a `chart_path` key).
static func load_by_index(level_list: Node, index: int) -> ChartData:
	var levels: Array = level_list.get("levels")
	if levels.is_empty():
		push_error("LevelLoader: level list is empty.")
		return ChartData.new()
	if index < 0 or index >= levels.size():
		push_error("LevelLoader: index %d out of range (0..%d)." % [index, levels.size() - 1])
		return ChartData.new()
	return load_chart(str(levels[index].get("chart_path", "")))


## Load whatever the list currently has centered/selected.
static func load_selected(level_list: Node) -> ChartData:
	return load_by_index(level_list, int(level_list.get("selected_index")))
