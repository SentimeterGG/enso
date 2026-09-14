# spawns scrolling notes in sync with playback position
class_name NoteScheduler
extends Resource

var playing = false


func start():
	playing = true
	pass


func process(
	note_manager: Node2D, music: AudioStreamPlayer, charts: ChartData, target_shape: Line2D
):
	if playing == true:
		var playback_pos = music.get_playback_position()
		var lead: float = note_manager.lane_length() / note_manager.px_per_sec
		while charts.notes.size() > 0 and playback_pos >= charts.note_time(0) / 1000.0 - lead:
			note_manager.spawn(charts.note_time(0) / 1000.0, charts.note_color(0))
			charts.notes.remove_at(0)
		while charts.shape_times.size() > 0:
			var shape_time: Array = charts.shape_time(0)
			if playback_pos >= shape_time[0] / 1000.0:
				target_shape.change(charts.shapes[0])
			target_shape.change(charts.shapes[0])
			if playback_pos >= shape_time[1] / 1000.0:
				charts.shapes.remove_at(0)
				charts.shape_times.remove_at(0)
			else:
				break
	pass


func end():
	playing = false
	pass
