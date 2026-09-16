class_name DiscordRichPresence
extends Node
## Discord Rich Presence in pure GDScript. No GDExtension, no Game SDK.
##
## Talks directly to the Discord client over its local IPC channel.
## A frame is [opcode u32][length u32] in little endian, then a JSON body.
## Handshake with your application id (op 0), then SET_ACTIVITY (op 1)
## when the presence changes.
##
## On Windows the channel is a named pipe, opened with FileAccess. On
## macOS and Linux it is a unix socket, which GDScript cannot open, so
## the addon bridges it through the system netcat with
## OS.execute_with_pipe (Godot 4.4+). On any platform where no channel
## is available (web, mobile, headless), this node does nothing.
## Discord not running is not an error either: the client retries alone.
##
## Note: Godot only opens Windows named pipes with the "\\?\pipe\name"
## path form. The usual "\\.\pipe\name" form fails with ERR_FILE_NOT_FOUND.
##
## Usage:
##     var presence := DiscordRichPresence.new()
##     presence.app_id = "1234567890123456789"
##     add_child(presence)
##     presence.set_activity({"details": "In the Hub", "state": "Level 12"})

## Emitted when the handshake completes. [param user] is the Discord user
## object (id, username, ...).
signal presence_connected(user: Dictionary)
## Emitted when the connection drops. The client retries by itself.
signal presence_disconnected

const _OP_HANDSHAKE: int = 0
const _OP_FRAME: int = 1
const _OP_CLOSE: int = 2
const _OP_PING: int = 3
const _OP_PONG: int = 4
## Discord can serve several IPC endpoints (main client, PTB, Canary).
const _MAX_PIPE_INDEX: int = 9
## Delay before looking for Discord again after a failure.
const _RETRY_SECONDS: float = 20.0

## Your Discord application id (from the Developer Portal). Set it before
## add_child, or call connect_now() after changing it.
@export var app_id: String = ""

var _pipe: FileAccess
## Process id of the netcat bridge on macOS and Linux, -1 when unused.
var _bridge_pid: int = -1
var _ready_received: bool = false
var _wanted_activity: Dictionary = {}
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
	# A dead bridge means Discord closed the socket (or was never there).
	if _bridge_pid != -1 and not OS.is_process_running(_bridge_pid):
		_drop()
		return
	_poll_frames()
	if _activity_dirty and _ready_received and _pipe:
		_activity_dirty = false
		var args: Dictionary = {"pid": OS.get_process_id()}
		# JSON null clears the presence; an empty object does not.
		args["activity"] = null if _wanted_activity.is_empty() else _wanted_activity
		_send(_OP_FRAME, {"cmd": "SET_ACTIVITY", "args": args, "nonce": str(_nonce)})
		_nonce += 1


## Restart the connection cycle, dropping the current connection if any.
## Safe to call at any time, needed after changing app_id.
func connect_now() -> void:
	_drop()
	_retry_left = 0.0
	set_process(_supported())


## Ask Discord to show [param activity] (the SET_ACTIVITY activity object:
## details, state, timestamps, assets, party, ...). Remembered across
## reconnects, and safe to call while Discord is closed.
func set_activity(activity: Dictionary) -> void:
	_wanted_activity = activity
	_activity_dirty = true


## Remove the presence but keep the connection.
func clear_activity() -> void:
	set_activity({})


func _supported() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return OS.get_name() in ["Windows", "macOS", "Linux"]


func _try_connect() -> void:
	if app_id.is_empty():
		return
	if OS.get_name() == "Windows":
		for index: int in _MAX_PIPE_INDEX + 1:
			# Only the "\\?\pipe\" path form works, see the class doc.
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
		# Skip non-sockets cheaply: DirAccess.get_files_at() does not
		# reliably list unix sockets, and spawning nc for every candidate
		# would attach to a dead bridge (only retried every 20s).
		if not _is_socket(path):
			continue
		var spawned: Dictionary = OS.execute_with_pipe(bridge, _bridge_args(bridge, path), false)
		if spawned.is_empty():
			continue
		# If nothing listens on the socket, netcat exits at once and the
		# dead-bridge check in _process falls back to the retry cycle.
		_bridge_pid = spawned["pid"]
		_attach(spawned["stdio"])
		return


func _attach(pipe: FileAccess) -> void:
	_pipe = pipe
	_ready_received = false
	_send(_OP_HANDSHAKE, {"v": 1, "client_id": app_id})


## macOS ships OpenBSD nc (has -U); on Linux the bridge must support unix
## sockets. NOTE: GNU netcat (/usr/bin/nc -> netcat 0.7.1 on Arch) has NO
## unix-socket support ("nc: invalid option -- 'U'"), while ncat and socat
## do. So prefer ncat/socat and only accept nc if its help shows -U/unix.
## socat uses different args, see _bridge_args.
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


## Probe whether a bridge binary can carry a unix socket.
func _bridge_supports_unix(bridge: String) -> bool:
	var base: String = bridge.get_file()
	if base == "socat" or base == "ncat":
		return true
	var output: Array = []
	# OpenBSD nc prints "-U" in usage; GNU netcat does not. Try -h/--help.
	if OS.execute(bridge, ["-h"], output) != 0 and OS.execute(bridge, ["--help"], output) != 0:
		return false
	var text: String = "\n".join(PackedStringArray(output)).to_lower()
	return text.contains("-u") and (text.contains("unix") or text.contains("unixsock"))


## Args for the bridge process: nc/ncat use "-U path",
## socat uses "STDIO UNIX-CONNECT:path".
func _bridge_args(bridge: String, path: String) -> PackedStringArray:
	if bridge.get_file() == "socat":
		return PackedStringArray(["STDIO", "UNIX-CONNECT:" + path])
	return PackedStringArray(["-U", path])


## test -S returns 0 only for sockets. FileAccess.file_exists and
## DirAccess.get_files_at do NOT reliably see unix sockets, so use this.
func _is_socket(path: String) -> bool:
	if OS.get_name() == "Windows":
		return false
	return OS.execute("test", ["-S", path]) == 0


## Discord resolves the socket dir as XDG_RUNTIME_DIR, TMPDIR, TMP, TEMP,
## then /tmp. Native arRPC (Vesktop) listens at $XDG_RUNTIME_DIR/discord-ipc-0.
## Flatpak Discord uses a subdirectory of the runtime dir; the Vesktop
## Flatpak socket appears on the host at .flatpak/dev.vencord.Vesktop/xdg-run.
## Build direct discord-ipc-0..9 candidates (no directory-listing dependency)
## plus any extra discord-ipc-* names found via guarded listing.
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
		# Supplement with listing for non-standard names. Guarded so a
		# missing Flatpak dir no longer logs "Couldn't open directory".
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
	# FileAccess reads are buffered: the first get_32() reads everything the
	# pipe holds into an internal buffer, and get_length() only sees the OS
	# pipe. So a frame's header and body must be read in the same pass:
	# after the header, a second get_length() check would report 0 while the
	# body sits in the buffer. Discord writes a frame in one write, so when
	# 8 bytes are visible the whole frame is readable.
	while _pipe and _pipe.get_length() >= 8:
		var op: int = _pipe.get_32()
		var length: int = _pipe.get_32()
		var body: Dictionary = {}
		if length > 0:
			var parsed: Variant = JSON.parse_string(
				_pipe.get_buffer(length).get_string_from_utf8())
			if parsed is Dictionary:
				body = parsed
		_handle_frame(op, body)


func _handle_frame(op: int, body: Dictionary) -> void:
	match op:
		_OP_FRAME:
			if not _ready_received and str(body.get("cmd", "")) == "DISPATCH" \
					and str(body.get("evt", "")) == "READY":
				_ready_received = true
				_activity_dirty = true  # Reassert the wanted presence.
				var user: Variant = (body.get("data", {}) as Dictionary).get("user", {})
				presence_connected.emit(user if user is Dictionary else {})
		_OP_PING:
			_send(_OP_PONG, body)
		_OP_CLOSE:
			_drop()


func _send(op: int, body: Dictionary) -> void:
	if _pipe == null:
		return
	var payload: PackedByteArray = JSON.stringify(body).to_utf8_buffer()
	_pipe.store_32(op)  # FileAccess defaults to little endian, the wire order.
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
