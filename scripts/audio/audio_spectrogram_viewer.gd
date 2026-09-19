# audio_spectrogram_viewer.gd — Audacity-style offline spectrogram viewer.
# Give it an audio file path and it renders the whole song as an Image
# shown on the child Sprite2D ($SpectrogramSprite).
# Width (in pixels) is proportional to song length: width = duration * pixels_per_second.
# Currently supports WAV (8-bit / 16-bit PCM, 32-bit float, mono or stereo -> mixed
# to mono). WAV is recommended because it is lossless — MP3/OGG smear FFT bins.
# This is a @tool script: it renders live in the editor, no need to press Play.
# RETURN: ImageTexture on SpectrogramSprite + spectrogram_ready(width, height, duration)
@tool
class_name AAudioSpectogramViewer
extends Node2D

signal spectrogram_ready(image_width: int, image_height: int, duration_sec: float)
signal spectrogram_failed(reason: String)

## Path to audio file. Accepts res://, user:// or absolute OS path (.wav).
@export var audio_path: String = ""

## When ON, changing any setting re-renders automatically in the editor.
@export var auto_refresh_in_editor: bool = true

## Horizontal resolution — higher = wider image for the same song length.
@export var pixels_per_second: float = 20.0:
	set(value):
		pixels_per_second = clampf(value, 1.0, 1000.0)
		_editor_setting_changed()

## FFT window. Must be power of two. 256 is a good speed/quality default.
## Image height will be fft_size / 2 (e.g. 256 -> 128 px tall).
@export var fft_size: int = 256:
	set(value):
		fft_size = _snap_pow2(clampi(value, 64, 2048))
		_editor_setting_changed()

## Dynamic range for display, in dB. Audacity defaults to roughly -60..0.
@export var min_db: float = -70.0:
	set(value):
		min_db = value
		_editor_setting_changed()
@export var max_db: float = -10.0:
	set(value):
		max_db = value
		_editor_setting_changed()
@export var color_gamma: float = 0.7:
	set(value):
		color_gamma = value
		_editor_setting_changed()
## True = bass at bottom like Audacity. False = bass at top.
@export var low_freq_at_bottom: bool = true:
	set(value):
		low_freq_at_bottom = value
		_editor_setting_changed()
## Hard cap so very long songs don't allocate giant textures.
@export var max_width: int = 2048:
	set(value):
		max_width = maxi(value, 64)
		_editor_setting_changed()

## Click to render now without entering Play mode.
@export_tool_button("Generate Now", "Callable") var generate_now_button = _on_editor_generate
## Click to clear the preview texture.
@export_tool_button("Clear Now", "Callable") var clear_now_button = _on_editor_clear

var duration_sec: float = 0.0
var mix_rate: int = 44100
var image_width: int = 0
var image_height: int = 0

var sprite: Sprite2D = null

var _hann: PackedFloat32Array = PackedFloat32Array()
var _is_generating: bool = false
var _pending_path: String = ""


## Queues a build; if one is already running, remembers the latest path and
## re-runs once at the end (keeps editor slider-drags smooth instead of dropping them).
func _request_build(path: String) -> void:
	if _is_generating:
		_pending_path = path
		return
	call_deferred("load_spectrogram", path)


## Any inspector setting changed: re-render in editor when auto-refresh is on.
func _editor_setting_changed() -> void:
	if not Engine.is_editor_hint():
		return
	if not auto_refresh_in_editor:
		return
	if not is_node_ready():
		return
	if audio_path == "" or _is_generating:
		return
	call_deferred("load_spectrogram", audio_path)


func _on_editor_generate() -> void:
	if audio_path == "":
		push_warning("AAudioSpectogramViewer: pick a .wav in audio_path first.")
		return
	_request_build(audio_path)


func _on_editor_clear() -> void:
	_pending_path = ""
	clear()


func _get_sprite() -> Sprite2D:
	if sprite == null:
		sprite = get_node_or_null("SpectrogramSprite") as Sprite2D
	return sprite


## Main entry point: takes the path of the file, decodes it and shows it as Sprite2D.
func load_spectrogram(path: String) -> void:
	if _is_generating:
		push_warning("AAudioSpectogramViewer: already generating, ignoring: " + path)
		return
	_is_generating = true
	path = path.strip_edges()
	audio_path = path
	_build_hann()
	var decoded := _load_mono_samples(path)
	if decoded.is_empty():
		_finish_build()
		return
	mix_rate = int(decoded["mix_rate"])
	var frame_count: int = decoded["frame_count"]
	duration_sec = float(frame_count) / float(maxi(mix_rate, 1))
	image_width = clampi(int(duration_sec * pixels_per_second), 64, max_width)
	image_height = fft_size / 2
	# Hop so the whole song fits exactly into image_width columns.
	var hop: float = float(frame_count) / float(image_width)
	var db_range := maxf(max_db - min_db, 1.0)
	var log10 := log(10.0)
	var lut_r := PackedByteArray()
	var lut_g := PackedByteArray()
	var lut_b := PackedByteArray()
	lut_r.resize(256)
	lut_g.resize(256)
	lut_b.resize(256)
	for li in range(256):
		var cc := _mag_to_color(pow(float(li) / 255.0, color_gamma))
		lut_r[li] = int(cc.r * 255.0)
		lut_g[li] = int(cc.g * 255.0)
		lut_b[li] = int(cc.b * 255.0)
	# Reused FFT buffers (avoids per-column allocation).
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	re.resize(fft_size)
	im.resize(fft_size)
	var buf := PackedByteArray()
	buf.resize(image_width * image_height * 3)
	# Loop invariants — computed once instead of every column/pixel.
	var norm := float(fft_size) * 0.5
	var inv_norm_sq := 1.0 / (norm * norm)
	var inv_db_range := 1.0 / db_range
	var width3 := image_width * 3
	var bin_for_row := PackedInt32Array()
	bin_for_row.resize(image_height)
	for row in range(image_height):
		bin_for_row[row] = row if not low_freq_at_bottom else (image_height - 1 - row)

	for col in range(image_width):
		var start := int(float(col) * hop - float(fft_size) * 0.5)
		_fill_windowed(decoded, start, re, im)
		_fft_inplace(re, im)
		var col3 := col * 3
		for row in range(image_height):
			var bin: int = bin_for_row[row]
			# power = |FFT bin|^2 — same result as sqrt()-then-20*log10(), no sqrt needed.
			var power := (re[bin] * re[bin] + im[bin] * im[bin]) * inv_norm_sq
			var db := 10.0 * log(maxf(power, 1e-16)) / log10
			var t := clampf((db - min_db) * inv_db_range, 0.0, 1.0)
			var li := int(t * 255.0)
			var off := row * width3 + col3
			buf[off] = lut_r[li]
			buf[off + 1] = lut_g[li]
			buf[off + 2] = lut_b[li]
		if col % 64 == 63 and is_inside_tree():
			await get_tree().process_frame
	var img := Image.create_from_data(image_width, image_height, false, Image.FORMAT_RGB8, buf)
	var tex := ImageTexture.create_from_image(img)
	var target := _get_sprite()
	if target == null:
		(
			spectrogram_failed
			. emit(
				"SpectrogramSprite node missing (scene must have a Sprite2D child named SpectrogramSprite)."
			)
		)
		push_error("AAudioSpectogramViewer: SpectrogramSprite child not found.")
		_finish_build()
		return
	target.texture = tex
	# Tell the editor the scene has unsaved preview changes (editor only, harmless at runtime).
	if Engine.is_editor_hint():
		queue_redraw()
	spectrogram_ready.emit(image_width, image_height, duration_sec)
	_finish_build()


## Shared exit for load_spectrogram: releases the lock, then runs the latest
## queued rebuild if one arrived mid-generation.
func _finish_build() -> void:
	_is_generating = false
	if _pending_path != "":
		var next := _pending_path
		_pending_path = ""
		call_deferred("load_spectrogram", next)


func clear() -> void:
	var target := _get_sprite()
	if target != null:
		target.texture = null
	duration_sec = 0.0
	image_width = 0
	image_height = 0


## Map a song-time in seconds to a local x offset on the sprite (sprite has centered=false).
func time_to_x(time_sec: float) -> float:
	if duration_sec <= 0.0:
		return 0.0
	return clampf(time_sec / duration_sec, 0.0, 1.0) * float(image_width)


func x_to_time(x: float) -> float:
	if image_width <= 0:
		return 0.0
	return clampf(x / float(image_width), 0.0, 1.0) * duration_sec


# --- decoding -------------------------------------------------------------


func _load_mono_samples(path: String) -> Dictionary:
	path = path.strip_edges()
	# 1) WAV: always parse the raw file. Never fall through to ResourceLoader here —
	# Godot imports .wav as QOA/ADPCM (AudioStreamWAV.data is NOT raw PCM), which would
	# only produce a misleading "format 3" error on top of the real one.
	if path.to_lower().ends_with(".wav"):
		if not FileAccess.file_exists(path):
			spectrogram_failed.emit("File not found: " + path)
			push_error("AAudioSpectogramViewer: file not found: " + path)
			return {}
		return _parse_wav_file(path)  # emits the specific reason on failure
	# 2) Non-wav: only Godot resources can even be attempted, and they are rejected
	# with a clear message (MP3/OGG compression smears spectrogram bins).
	if ResourceLoader.exists(path) or FileAccess.file_exists(path):
		spectrogram_failed.emit(
			"Only .wav is supported for spectrogram (got: " + path + "). Convert to WAV first."
		)
		push_error("AAudioSpectogramViewer: only .wav supported, got " + path)
		return {}
	spectrogram_failed.emit("File not found: " + path)
	push_error("AAudioSpectogramViewer: file not found: " + path)
	return {}


func _samples_from_wav_stream(wav: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var bytes := wav.data
	if bytes.is_empty():
		return out
	var channels := 2 if wav.stereo else 1
	match wav.format:
		AudioStreamWAV.FORMAT_8_BITS:
			var frames := bytes.size() / channels
			out.resize(frames)
			for i in range(frames):
				var acc := 0.0
				for c in range(channels):
					acc += (float(bytes[i * channels + c]) - 128.0) / 128.0
				out[i] = acc / float(channels)
		AudioStreamWAV.FORMAT_16_BITS:
			var frames := bytes.size() / (2 * channels)
			out.resize(frames)
			for i in range(frames):
				var acc := 0.0
				for c in range(channels):
					acc += float(bytes.decode_s16((i * channels + c) * 2)) / 32768.0
				out[i] = acc / float(channels)
		_:
			push_error(
				(
					"AAudioSpectogramViewer: only 8/16-bit WAV supported (file uses format %d). Re-export as 16-bit PCM."
					% wav.format
				)
			)
	return out


## Minimal RIFF/WAV parser: PCM 8/16/24/32-bit + IEEE float 32/64-bit (incl.
## WAVE_FORMAT_EXTENSIBLE), any channel count, skips extra chunks (LIST/bext/...).
## Returns a decode CONTEXT (raw bytes + format info) rather than decoded
## samples — actual decoding happens lazily, per FFT window, in _fill_windowed().
## A typical spectrogram only ever reads a small fraction of a song's samples
## (one ~256-sample window per column), so decoding all of them up front wastes
## the vast majority of that work.
func _parse_wav_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		spectrogram_failed.emit("Could not open file: " + path)
		return {}
	var riff := f.get_buffer(12)
	if riff.size() < 12 or riff.slice(0, 4) != PackedByteArray([0x52, 0x49, 0x46, 0x46]):
		spectrogram_failed.emit("Not a WAV file: " + path)
		return {}
	var audio_format := 1
	var channels := 1
	var sample_rate := 44100
	var bits := 16
	var data_bytes := PackedByteArray()
	while not f.eof_reached():
		var chunk_h := f.get_buffer(8)
		if chunk_h.size() < 8:
			break
		var chunk_id := chunk_h.slice(0, 4).get_string_from_ascii()
		var chunk_size := chunk_h.decode_u32(4)
		var chunk_data := f.get_buffer(chunk_size)
		# WAV chunks are word-aligned: skip the pad byte after odd sizes.
		if chunk_size % 2 == 1 and not f.eof_reached():
			f.get_buffer(1)
		if chunk_id == "fmt " and chunk_data.size() >= 16:
			audio_format = chunk_data.decode_u16(0)
			channels = maxi(chunk_data.decode_u16(2), 1)
			sample_rate = chunk_data.decode_u32(4)
			bits = chunk_data.decode_u16(14)
			# WAVE_FORMAT_EXTENSIBLE (0xFFFE): real format lives in the SubFormat GUID.
			if audio_format == 0xFFFE and chunk_data.size() >= 26:
				audio_format = chunk_data.decode_u16(24)
		elif chunk_id == "data":
			data_bytes = chunk_data
			break # ignore chunks after data
	if data_bytes.is_empty():
		spectrogram_failed.emit("WAV has no data chunk: " + path)
		return {}
	var supported := (
		(audio_format == 1 and (bits == 8 or bits == 16 or bits == 24 or bits == 32))
		or (audio_format == 3 and (bits == 32 or bits == 64))
	)
	if not supported:
		spectrogram_failed.emit("Unsupported WAV: format=%d bits=%d. Re-export as 16-bit PCM." % [audio_format, bits])
		return {}
	var bytes_per_frame := (bits / 8) * channels
	var frame_count := data_bytes.size() / bytes_per_frame
	return {
		"data": data_bytes,
		"channels": channels,
		"bits": bits,
		"audio_format": audio_format,
		"bytes_per_frame": bytes_per_frame,
		"frame_count": frame_count,
		"mix_rate": sample_rate,
	}


# --- FFT -----------------------------------------------------------------
## Decodes ONE frame (all channels, downmixed to mono) at the given frame index.
## Called only for the handful of frames each FFT window actually needs — not
## the whole song.
func _decode_mono_frame(ctx: Dictionary, frame_idx: int) -> float:
	var data: PackedByteArray = ctx["data"]
	var channels: int = ctx["channels"]
	var bits: int = ctx["bits"]
	var audio_format: int = ctx["audio_format"]
	var base: int = frame_idx * ctx["bytes_per_frame"]
	var acc := 0.0
	if audio_format == 1 and bits == 8:
		for c in range(channels):
			acc += (float(data[base + c]) - 128.0) / 128.0
	elif audio_format == 1 and bits == 16:
		for c in range(channels):
			acc += float(data.decode_s16(base + c * 2)) / 32768.0
	elif audio_format == 1 and bits == 24:
		for c in range(channels):
			var o := base + c * 3
			var v := int(data[o]) | (int(data[o + 1]) << 8) | (int(data[o + 2]) << 16)
			if v >= 0x800000:
				v -= 0x1000000
			acc += float(v) / 8388608.0
	elif audio_format == 1 and bits == 32:
		for c in range(channels):
			acc += float(data.decode_s32(base + c * 4)) / 2147483648.0
	elif audio_format == 3 and bits == 32:
		for c in range(channels):
			acc += data.decode_float(base + c * 4)
	elif audio_format == 3 and bits == 64:
		for c in range(channels):
			acc += data.decode_double(base + c * 8)
	return acc / float(channels)


func _build_hann() -> void:
	_hann.resize(fft_size)
	for i in range(fft_size):
		_hann[i] = 0.5 - 0.5 * cos(TAU * float(i) / float(fft_size))


func _fill_windowed(ctx: Dictionary, start_frame: int, re: PackedFloat32Array, im: PackedFloat32Array) -> void:
	var frame_count: int = ctx["frame_count"]
	for i in range(fft_size):
		var frame_idx := start_frame + i
		var s := 0.0
		if frame_idx >= 0 and frame_idx < frame_count:
			s = _decode_mono_frame(ctx, frame_idx) * _hann[i]
		re[i] = s
		im[i] = 0.0


## Iterative radix-2 Cooley-Tukey, in place. n must be a power of two.
static func _fft_inplace(re: PackedFloat32Array, im: PackedFloat32Array) -> void:
	var n := re.size()
	var j := 0
	for i in range(1, n):
		var bit := n >> 1
		while j & bit != 0:
			j ^= bit
			bit >>= 1
		j ^= bit
		if i < j:
			var tmp := re[i]
			re[i] = re[j]
			re[j] = tmp
			tmp = im[i]
			im[i] = im[j]
			im[j] = tmp
	var length := 2
	while length <= n:
		var angle := -TAU / float(length)
		var w_re := cos(angle)
		var w_im := sin(angle)
		var half := length >> 1
		for i in range(0, n, length):
			var cur_re := 1.0
			var cur_im := 0.0
			for k in range(half):
				var u_re := re[i + k]
				var u_im := im[i + k]
				var v_re := re[i + k + half] * cur_re - im[i + k + half] * cur_im
				var v_im := re[i + k + half] * cur_im + im[i + k + half] * cur_re
				re[i + k] = u_re + v_re
				im[i + k] = u_im + v_im
				re[i + k + half] = u_re - v_re
				im[i + k + half] = u_im - v_im
				var nxt_re := cur_re * w_re - cur_im * w_im
				cur_im = cur_re * w_im + cur_im * w_re
				cur_re = nxt_re
		length <<= 1


static func _snap_pow2(v: int) -> int:
	var p := 64
	while p < v:
		p <<= 1
	return mini(p, 2048)


## Audacity-ish gradient: black -> purple -> red -> yellow -> white.
static func _mag_to_color(t: float) -> Color:
	var c := Color.BLACK
	if t <= 0.0:
		return c
	elif t < 0.3:
		return Color(0.02, 0.02, 0.05).lerp(Color(0.35, 0.1, 0.7), t / 0.3)
	elif t < 0.55:
		return Color(0.35, 0.1, 0.7).lerp(Color(0.95, 0.25, 0.15), (t - 0.3) / 0.25)
	elif t < 0.8:
		return Color(0.95, 0.25, 0.15).lerp(Color(1.0, 0.9, 0.35), (t - 0.55) / 0.25)
	else:
		return Color(1.0, 0.9, 0.35).lerp(Color.WHITE, (t - 0.8) / 0.2)
