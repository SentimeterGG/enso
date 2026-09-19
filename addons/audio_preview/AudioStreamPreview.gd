@tool
extends Control

## Immediate-mode osu!-style waveform view: a plain Control, no textures.
## All visuals come from _draw() below, so there is nothing texture-related
## to maintain — no TextureRect, no ImageTexture, no GPU size limits.
##
## History: sizing one texture to song_length * px_per_sec went BLANK past
## the GPU texture limit at 600 px/sec; the windowed-texture follow-up fixed
## the blank but could never finish a render while playing (every scroll
## frame aborted the in-flight async render — a livelock).
##
## Now there are no textures at all. The song's envelope is computed ONCE
## into a tiny peak cache (see voice_preview_generator.gd) and _draw()
## paints the visible 1px bars straight from it. update_view() just stores
## the view and queue_redraw()s — synchronous, nothing to abort — so the
## waveform follows playback, scrub and zoom every frame.
##
## The coordinate system is unchanged (column-local x = time * px_per_sec):
## the rect is positioned at window_start * px_per_sec, so markers and
## scrolling in mapping.gd keep working untouched. Stays a Control, so
## mouse_filter / gui_input / get_global_rect() keep working too.

signal generation_started
signal generation_progress(normalized_progress)
signal generation_completed

## Cap for the drawn window — bounds _draw() cost at any zoom.
const MAX_DRAW_WIDTH := 16000
## Drawn window = visible width + this margin on each side, so the rect only
## repositions when the playhead nears an edge instead of every frame.
const WINDOW_MARGIN_PX := 1400.0

var voice_preview_generator
var stream: AudioStreamWAV = null
var stream_length := 0.0

var bar_color := Color(0.82, 0.89, 1.0)
var played_bar_color := Color(0.45, 0.5, 0.6)
var center_color := Color(1, 1, 1, 0.35)
## Translucent body under the bars (option C composite: smooth fill + crisp
## 1px transient lines on top).
var envelope_color := Color(0.55, 0.63, 0.85, 0.30)

var _view_now := 0.0
var _view_width := 720.0
var _peaks_ready := false
## Cached envelope geometry, rebuilt only when the window/zoom/peaks change
## (never per frame): closed fill polygon + per-column bar spans in pixels.
var _env_points := PackedVector2Array()
var _bar_spans := PackedVector2Array()
var _cache_t0 := 0.0
var _cache_pps := 0.0
var _cache_h := -1.0
## Bumped on every song change so a stale async pass can never overwrite a
## newer one (a song swapped mid-compute restarts instead of going blank).
var _song_gen := 0

@export var px_per_sec: float = 100.0:
	set(new_value):
		px_per_sec = maxf(1.0, new_value)
		if is_node_ready():
			_reposition()
			queue_redraw()

@export_file("*.wav") var stream_path: String:
	set(new_path):
		stream_path = new_path
		_update_preview()


func _ready():
	voice_preview_generator = preload("res://addons/audio_preview/voice_preview_generator.tscn").instantiate()
	add_child(voice_preview_generator)
	voice_preview_generator.generation_progress.connect(_on_generation_progress)
	_update_preview()


## Called by the editor every scroll/zoom/seek. Synchronous: repositions the
## rect when the playhead nears the window edge, then redraws. Safe every
## frame — there is no async render left to abort.
func update_view(now_sec: float, pps: float, view_width_px: float) -> void:
	_view_now = maxf(0.0, now_sec)
	_view_width = maxf(64.0, view_width_px)
	var clamped := clampf(pps, 1.0, 600.0)
	if not is_equal_approx(clamped, px_per_sec):
		px_per_sec = clamped # setter repositions + redraws
		return
	_reposition()
	queue_redraw()


## Back-compat: zooming is now just a view update.
func set_display_zoom(new_px_per_sec: float) -> void:
	update_view(_view_now, new_px_per_sec, _view_width)


func _draw() -> void:
	if not _peaks_ready or voice_preview_generator == null:
		return
	if not voice_preview_generator.has_peaks():
		return
	var h := size.y
	if h <= 0.0:
		return
	if _env_points.is_empty() or _cache_h != h:
		var fb_pps := maxf(1.0, px_per_sec)
		_rebuild_cache(position.x / fb_pps, fb_pps, int(size.x), h)
		if _env_points.is_empty():
			return
	var center := h * 0.5
	# Smooth body first, crisp transient bars on top, center line last.
	draw_colored_polygon(_env_points, envelope_color)
	var n := _bar_spans.size()
	for i in range(n):
		var span_y := _bar_spans[i]
		if absf(span_y.x - span_y.y) < 0.5:
			continue # silence/sub-pixel: envelope + center line cover it
		var col := played_bar_color if _cache_t0 + float(i + 1) / _cache_pps <= _view_now else bar_color
		var x := float(i) + 0.5
		draw_line(Vector2(x, span_y.x), Vector2(x, span_y.y), col)
	draw_line(Vector2(0.0, center), Vector2(size.x, center), center_color)


func _update_preview():
	if not voice_preview_generator:
		return

	if stream_path in ["", "res://", "user://"]:
		queue_redraw()
		return

	stream = load(stream_path) as AudioStreamWAV
	if stream == null:
		return # e.g. non-wav path: keep the previous peaks
	_song_gen += 1
	var gen := _song_gen
	stream_length = stream.get_length() if stream else 0.0
	_peaks_ready = false
	_reposition()
	queue_redraw()
	emit_signal("generation_started")
	# Serialize against any in-flight pass for the previous song.
	await voice_preview_generator.abort()
	if gen != _song_gen:
		return
	var ok: bool = await voice_preview_generator.compute_peaks(stream)
	if gen != _song_gen:
		return
	if not ok:
		return
	_peaks_ready = true
	stream_length = voice_preview_generator.song_length
	_reposition()
	queue_redraw()
	emit_signal("generation_completed")


## Positions/sizes the rect for the current view. Column-local
## x = time * px_per_sec, so _draw() can derive window start from position.
func _reposition() -> void:
	if stream == null or stream_length <= 0.0:
		return
	var span_px := minf(_view_width + WINDOW_MARGIN_PX * 2.0, float(MAX_DRAW_WIDTH))
	var span_sec := minf(span_px / maxf(1.0, px_per_sec), stream_length)
	if span_sec < 0.01:
		return
	# Playhead sits ~1/4 from the left so there is room to read ahead.
	var t0 := clampf(_view_now - span_sec * 0.25, 0.0, maxf(0.0, stream_length - span_sec))
	var w := float(maxi(1, int(round((minf(stream_length, t0 + span_sec) - t0) * px_per_sec))))
	position.x = t0 * px_per_sec
	size.x = w
	custom_minimum_size.x = w
	_rebuild_cache(t0, maxf(1.0, px_per_sec), int(w), size.y)


## Builds the cached envelope + bar geometry for one window. Runs only on
## window/zoom/peaks/height changes — _draw() reuses the cache every frame.
func _rebuild_cache(t0: float = -1.0, pps: float = -1.0, w: int = -1, h: float = -1.0) -> void:
	_env_points = PackedVector2Array()
	_bar_spans = PackedVector2Array()
	if not _peaks_ready or voice_preview_generator == null:
		return
	if not voice_preview_generator.has_peaks():
		return
	if t0 < 0.0:
		t0 = _cache_t0
	if pps <= 0.0:
		pps = _cache_pps if _cache_pps > 0.0 else maxf(1.0, px_per_sec)
	if w < 0:
		w = _bar_spans.size()
	if h < 0.0:
		h = size.y
	if w <= 0 or h <= 0.0:
		return
	_cache_t0 = t0
	_cache_pps = pps
	_cache_h = h
	var center := h * 0.5
	var half := center - 1.0
	_bar_spans.resize(w)
	var tops := PackedVector2Array()
	tops.resize(w)
	var bots := PackedVector2Array()
	bots.resize(w)
	for i in range(w):
		var span: Vector2i = voice_preview_generator.sample_range(
			t0 + float(i) / pps, t0 + float(i + 1) / pps
		)
		var y_top := clampf(center - float(span.y - 128) / 127.0 * half, 0.0, h)
		var y_bot := clampf(center - float(span.x - 128) / 127.0 * half, 0.0, h)
		_bar_spans[i] = Vector2(y_top, y_bot)
		tops[i] = Vector2(float(i) + 0.5, y_top)
		bots[w - 1 - i] = Vector2(float(i) + 0.5, y_bot) # reversed order, own x
	_env_points = tops + bots # closed loop: top L->R, bottom R->L


func _on_generation_progress(normalized_progress: float):
	emit_signal("generation_progress", normalized_progress)
