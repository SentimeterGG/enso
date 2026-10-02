extends Node

var presence := DiscordRichPresence.new()

const APP_ID := "1549421692244201492"


func _ready() -> void:
	presence.app_id = APP_ID
	add_child(presence)

	set_activity("in Main Menu", "Chilling...")


## Sets the discord activity
func set_activity(details: String, state: String) -> void:
	presence.set_activity(
		{
			"details": details,
			"state": state,
			"timestamps": {"start": int(Time.get_unix_time_from_system())},
			"assets": {"large_image": "enso-logo"}
		}
	)
