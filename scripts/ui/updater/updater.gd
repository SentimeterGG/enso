extends Control

@onready var http_request: HTTPRequest = $HTTPRequest
var curr_version = null


func check_update(current_ver: String):
	curr_version = current_ver
	http_request.request(
		"https://api.github.com/repos/SentimeterGG/enso/releases",
		["Accept: application/vnd.github+json"],
		HTTPClient.METHOD_GET
	)
	pass


func compare(latest_ver: String):
	if curr_version != latest_ver:
		print("Outdated!")
		print("current: " + curr_version + ", latest: " + latest_ver)
		pass


func _on_http_request_request_completed(
	_result: int, _response_code: int, headers: PackedStringArray, body: PackedByteArray
) -> void:
	var string = body.get_string_from_utf8()
	var dict: Array = JSON.parse_string(string)
	var latest_version = dict[0]["tag_name"]
	compare(latest_version)
	pass  # Replace with function body.
