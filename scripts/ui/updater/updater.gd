extends Control

@onready var http_request: HTTPRequest = $HTTPRequest
var curr_version = null


func check_update(current_ver: String):
	curr_version = current_ver
	http_request.request(
		"https://api.github.com/repos/SentimeterGG/enso/releases",
		["Accept: application/vnd.github+json", "User-Agent: enso-client"],
		HTTPClient.METHOD_GET
	)
	pass


func compare(latest_ver: String) -> int:
	var result := compare_versions(str(curr_version), latest_ver)
	if result < 0:
		print("Outdated!")
		print("current: " + str(curr_version) + ", latest: " + latest_ver)
	else:
		print("Latest Update")
	return result


static func compare_versions(a: String, b: String) -> int:
	var pa := _parse_version(a)
	var pb := _parse_version(b)
	for i in range(3):
		if pa.core[i] != pb.core[i]:
			return -1 if pa.core[i] < pb.core[i] else 1
	if pa.pre.is_empty() and pb.pre.is_empty():
		return 0
	if pa.pre.is_empty():
		return 1
	if pb.pre.is_empty():
		return -1
	if pa.pre == pb.pre:
		return 0
	return -1 if pa.pre < pb.pre else 1


static func _parse_version(v: String) -> Dictionary:
	var s := v.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1).strip_edges()
	var pre := ""
	var dash := s.find("-")
	var core_str := s
	if dash != -1:
		core_str = s.substr(0, dash)
		pre = s.substr(dash + 1).to_lower()
	var core: Array[int] = [0, 0, 0]
	var parts := core_str.split(".")
	for i in range(mini(parts.size(), 3)):
		var p := parts[i].strip_edges()
		core[i] = p.to_int() if p.is_valid_int() else 0
	return {"core": core, "pre": pre}


func _on_http_request_request_completed(
	_result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray
) -> void:
	if response_code == HTTPClient.RESPONSE_OK:
		var string = body.get_string_from_utf8()
		var dict = JSON.parse_string(string)
		var latest_version = dict[0]["tag_name"]
		compare(latest_version)
	pass  # Replace with function body.
