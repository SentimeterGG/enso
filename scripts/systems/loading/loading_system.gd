extends Control
class_name LoadingSystem

var progress = []
@export_file("*.tscn") var sceneName: String
var sceneLoadStatus = 0


func load_scene():
	ResourceLoader.load_threaded_request(sceneName)


func _process(_delta: float) -> void:
	sceneLoadStatus = ResourceLoader.load_threaded_get_status(sceneName, progress)
	if sceneLoadStatus == ResourceLoader.THREAD_LOAD_LOADED:
		var loadedScene = ResourceLoader.load_threaded_get(sceneName)
		get_tree().change_scene_to_packed(loadedScene)
