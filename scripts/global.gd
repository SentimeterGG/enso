extends Node
var current_chart: ChartData = null

var save_file_path = "user://ENSO_FILES/"


# Settings and Main Menu variables.
var settingsData = SettingsData.new()

func _ready():
	DirAccess.make_dir_recursive_absolute(save_file_path)
	load_all_data()
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if settingsData.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)


func save(resource, save_filename):
	ResourceSaver.save(resource, save_file_path + save_filename)
	

func load_all_data():
	settingsData = load_data(SettingsData)
	



func load_data(res_class: Resource):
	var temp = res_class.new()
	var path = save_file_path + temp.save_file_name
	
	if FileAccess.file_exists(path):
		var loaded = ResourceLoader.load(path)
		if loaded:
			return loaded.duplicate(true)
		else:
			push_warning("Failed to load, creating new: " + path)
	else:
		save(temp, temp.save_file_name)
	
	# ALWAYS return something
	return temp
