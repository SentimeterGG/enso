extends Control
class_name LoadingSystem

var progress  = []
@export_file("*.tscn") var sceneName: String
var sceneLoadStatus = 0

# Called when the node enters the scene tree for the first time.
func load_scene():
	ResourceLoader.load_threaded_request(sceneName)
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	sceneLoadStatus = ResourceLoader.load_threaded_get_status(sceneName, progress)
	if sceneLoadStatus == ResourceLoader.THREAD_LOAD_LOADED:
		var loadedScene = ResourceLoader.load_threaded_get(sceneName)
		get_tree().change_scene_to_packed(loadedScene)
