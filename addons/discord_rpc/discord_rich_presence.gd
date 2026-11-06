class_name DiscordRichPresence
extends Node

signal presence_connected(user: Dictionary)
signal presence_disconnected

const _OP_HANDSHAKE: int = 0
const _OP_FRAME: int = 1
const _OP_CLOSE: int = 2
const _OP_PING: int = 3
const _OP_PONG: int = 4
const _MAX_PIPE_INDEX: int = 9
const _RETRY_SECONDS: float = 20.0

@export var app_id: String = ""

var _pipe: FileAccess
var _bridge_pid: int = -1
var _ready_received: bool = false
var _wanted_activity: Dictionary = { }
var _activity_dirty: bool = false
var _retry_left: float = 0.0
var _nonce: int = 0


func _ready() -> void:
	connect_now()


func _exit_tree() -> void:
	_drop()


func _process(delta: float) -> void:
	if _pipe == null:
		_retry_left -= delta
		if _retry_left <= 0.0:
			_retry_left = _RETRY_SECONDS
			_try_connect()
		return
	if _bridge_pid != -1 and not OS.is_process_running(_bridge_pid):
		_drop()
		return
	_poll_frames()
	if _activity_dirty and _ready_received and _pipe:
		_activity_dirty = false
		var args: Dictionary = { "pid": OS.get_process_id() }
		args["activity"] = null if _wanted_activity.is_empty() else _wanted_activity
		_send(_OP_FRAME, { "cmd": "SET_ACTIVITY", "args": args, "nonce": str(_nonce) })
		_nonce += 1


func connect_now() -> void:
	_drop()
	_retry_left = 0.0
	set_process(_supported())


func set_activity(activity: Dictionary) -> void:
	_wanted_activity = activity
	_activity_dirty = true


func clear_activity() -> void:
	set_activity({ })


func _supported() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return OS.get_name() in ["Windows", "macOS", "Linux"]


func _try_connect() -> void:
	if app_id.is_empty():
		return
	if OS.get_name() == "Windows":
		for index: int in _MAX_PIPE_INDEX + 1:
			var path: String = "\\\\?\\pipe\\discord-ipc-%d" % index
			var pipe: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE)
			if pipe == null:
				continue
			_attach(pipe)
			return
		return
	var bridge: String = _find_bridge()
	if bridge.is_empty():
		return
	for path: String in _unix_socket_paths():
		if not _is_socket(path):
			continue
		var spawned: Dictionary = OS.execute_with_pipe(bridge, _bridge_args(bridge, path), false)
		if spawned.is_empty():
			continue
		_bridge_pid = spawned["pid"]
		_attach(spawned["stdio"])
		return


func _attach(pipe: FileAccess) -> void:
	_pipe = pipe
	_ready_received = false
	_send(_OP_HANDSHAKE, { "v": 1, "client_id": app_id })


func _find_bridge() -> String:
	for name: String in ["ncat", "socat", "nc"]:
		var output: Array = []
		if OS.execute("which", [name], output) != 0:
			continue
		var bridge: String = str(output[0]).strip_edges()
		if bridge.is_empty():
			continue
		if _bridge_supports_unix(bridge):
			return bridge
	return ""


func _bridge_supports_unix(bridge: String) -> bool:
	var base: String = bridge.get_file()
	if base == "socat" or base == "ncat":
		return true
	var output: Array = []
	if OS.execute(bridge, ["-h"], output) != 0 and OS.execute(bridge, ["--help"], output) != 0:
		return false
	var text: String = "\n".join(PackedStringArray(output)).to_lower()
	return text.contains("-u") and (text.contains("unix") or text.contains("unixsock"))


func _bridge_args(bridge: String, path: String) -> PackedStringArray:
	if bridge.get_file() == "socat":
		return PackedStringArray(["STDIO", "UNIX-CONNECT:" + path])
	return PackedStringArray(["-U", path])


func _is_socket(path: String) -> bool:
	if OS.get_name() == "Windows":
		return false
	return OS.execute("test", ["-S", path]) == 0


func _unix_socket_paths() -> PackedStringArray:
	var dirs: PackedStringArray = []
	for env: String in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"]:
		var value: String = OS.get_environment(env)
		if value.is_empty() or dirs.has(value):
			continue
		dirs.append(value)
	if not dirs.has("/tmp"):
		dirs.append("/tmp")
	var runtime: String = OS.get_environment("XDG_RUNTIME_DIR")
	if not runtime.is_empty():
		for sub: String in [
			"app/com.discordapp.Discord",
			"snap.discord",
			".flatpak/dev.vencord.Vesktop/xdg-run",
		]:
			var full: String = runtime.path_join(sub)
			if not dirs.has(full):
				dirs.append(full)
	var paths: PackedStringArray = []
	for dir: String in dirs:
		for index: int in _MAX_PIPE_INDEX + 1:
			var candidate: String = dir.path_join("discord-ipc-%d" % index)
			if not paths.has(candidate):
				paths.append(candidate)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var files: PackedStringArray = DirAccess.get_files_at(dir)
		for file: String in files:
			if file.begins_with("discord-ipc-"):
				var listed: String = dir.path_join(file)
				if not paths.has(listed):
					paths.append(listed)
	return paths


func _poll_frames() -> void:
	while _pipe and _pipe.get_length() >= 8:
		var op: int = _pipe.get_32()
		var length: int = _pipe.get_32()
		var body: Dictionary = { }
		if length > 0:
			var parsed: Variant = JSON.parse_string(_pipe.get_buffer(length).get_string_from_utf8())
			if parsed is Dictionary:
				body = parsed
		_handle_frame(op, body)


func _handle_frame(op: int, body: Dictionary) -> void:
	match op:
		_OP_FRAME:
			if (
				not _ready_received and str(body.get("cmd", "")) == "DISPATCH"
				and str(body.get("evt", "")) == "READY"
			):
				_ready_received = true
				_activity_dirty = true # Reassert the wanted presence.
				var user: Variant = (body.get("data", { }) as Dictionary).get("user", { })
				presence_connected.emit(user if user is Dictionary else { })
		_OP_PING:
			_send(_OP_PONG, body)
		_OP_CLOSE:
			_drop()


func _send(op: int, body: Dictionary) -> void:
	if _pipe == null:
		return
	var payload: PackedByteArray = JSON.stringify(body).to_utf8_buffer()
	_pipe.store_32(op) # FileAccess defaults to little endian, the wire order.
	_pipe.store_32(payload.size())
	_pipe.store_buffer(payload)
	_pipe.flush()
	if _pipe.get_error() != OK:
		_drop()


func _drop() -> void:
	if _bridge_pid != -1:
		OS.kill(_bridge_pid)
		_bridge_pid = -1
	_pipe = null
	if _ready_received:
		_ready_received = false
		presence_disconnected.emit()
	_retry_left = _RETRY_SECONDS
