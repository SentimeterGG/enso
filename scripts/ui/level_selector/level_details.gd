extends VBoxContainer

const TIERS := ["EASY", "NORMAL", "HARD", "EXPERT", "MASTER"]
const PIP_FILLED := Color(1, 0, 0, 1)
const PIP_FLASH := Color(1, 1, 1, 1)
const PIP_EMPTY := Color(0.2303, 0.2303, 0.2303, 1)
const GLYPHS := "#%&*+=<>/|?0123456789ABCDEF"
const PIP_FLASH_SEC := 0.1
const PIP_STAGGER_SEC := 0.07 # delay between pips; 0.0 flashes them all together
const PIP_START_DELAY := 0.2

var _decode_tweens: Dictionary = { } # Label -> Tween
var _decode_targets: Dictionary = { } # Label -> String
var _pips_shown := 0 # how many pips are currently lit (target state)
var _pip_tween: Tween = null
var _banner_tween: Tween = null
var _banner_path := ""

@onready var title_label: Label = $"Profile/ProfileDetails/TitleContainer/Title"
@onready var source_label: Label = $"Profile/ProfileDetails/SourceContainer/SourceValue"
@onready var mapper_label: Label = $"Profile/ProfileDetails/MapperContainer/MapperValue"
@onready var bpm_label: Label = $"Level/BPM/MarginContainer/VBoxContainer/Value"
@onready var song_banner: TextureRect = $"Profile/TextureRect"
@onready var song_length_label: Label = $"Level/Length/MarginContainer/VBoxContainer/Value"
@onready var difficulty_label: Label = $"Level/Difficulty/MarginContainer/VBoxContainer/VBoxContainer/Value"
@onready var pipe_parent: HBoxContainer = $"Level/Difficulty/MarginContainer/VBoxContainer/VBoxContainer/Pipe"


func refresh(chart_path: String) -> void:
	var metadata = ChartParser.parse_metadata(chart_path)
	_setup_details(metadata, chart_path)
	_setup_difficulty_pips(metadata)


func decode_text(
	label: Label,
	target: String,
	delay: float = 0.0,
	duration: float = 0.48,
	digits_only: bool = false,
) -> void:
	if _decode_targets.get(label, null) == target:
		return
	_decode_targets[label] = target

	var old: Tween = _decode_tweens.get(label, null)
	if old != null and old.is_valid():
		old.kill()

	if target.is_empty():
		label.text = ""
		return

	var tw := create_tween()
	_decode_tweens[label] = tw
	tw.tween_interval(delay)
	tw.tween_method(_set_decoded.bind(label, target, digits_only), 0.0, 1.0, duration)


func _setup_difficulty_pips(metadata: Dictionary):
	var od := int(str(metadata.overall_difficulty))
	if od >= 8000:
		od = int(od / 1000.0)
	od = clampi(od, 1, 10)
	var tier := 0
	if od <= 2:
		tier = 0
	elif od <= 4:
		tier = 1
	elif od <= 6:
		tier = 2
	elif od <= 8:
		tier = 3
	else:
		tier = 4
	decode_text(difficulty_label, TIERS[tier], 0.04, 0.48)
	_set_pips(tier)


func _setup_details(metadata: Dictionary, chart_path: String):
	var song = Global.load_safely(chart_path.get_base_dir().path_join(str(metadata.song)).simplify_path())
	var length: int
	if song:
		length = song.get_length()
	var bg_path = chart_path.get_base_dir().path_join(metadata.bg).simplify_path()
	decode_text(title_label, str(metadata.name).strip_edges().to_upper(), 0.04, 0.48)
	decode_text(source_label, str(metadata.source).strip_edges(), 0.04, 0.48)
	decode_text(mapper_label, str(metadata.mapper).strip_edges(), 0.04, 0.48)
	decode_text(bpm_label, str(metadata.bpm).strip_edges(), 0.04, 0.48)
	decode_text(
		song_length_label,
		"%d:%02d" % [int(float(length) / 60), int(length) % 60],
		0.04,
		0.48,
	)
	var resource_call = Global.load_safely_async(bg_path)
	var loaded_image = await resource_call.completed
	_animate_banner(bg_path, loaded_image)


func _animate_banner(path: String, tex: Texture2D) -> void:
	if path == _banner_path:
		return # same banner: don't replay
	_banner_path = path

	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()

	song_banner.texture = tex
	song_banner.pivot_offset = song_banner.size * 0.5
	song_banner.scale = Vector2(0.84, 0.84)
	song_banner.modulate = Color(2.2, 2.2, 2.2, 1.0) # bright flash

	_banner_tween = create_tween().set_parallel(true)
	_banner_tween.tween_property(song_banner, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(song_banner, "modulate", Color.WHITE, 0.3) \
			.set_ease(Tween.EASE_OUT)


func _set_decoded(t: float, label: Label, target: String, digits_only: bool) -> void:
	label.text = _scramble(target, t, digits_only)


func _scramble(target: String, t: float, digits_only: bool) -> String:
	if t >= 1.0:
		return target
	var revealed := int(t * target.length())
	var out := ""
	for i in target.length():
		var ch := target[i]
		if i < revealed or ch == " " or (digits_only and not ch.is_valid_int()):
			out += ch
		elif digits_only:
			out += str(randi() % 10)
		else:
			out += GLYPHS[randi() % GLYPHS.length()]
	return out


func _set_pips(tier: int) -> void:
	var count := _get_target_pip_count(tier)

	_kill_pip_tween()
	_sync_pip_colors()

	if count == _pips_shown:
		return

	_animate_pips(count)


func _get_target_pip_count(tier: int) -> int:
	return clampi(tier + 1, 0, pipe_parent.get_child_count())


func _kill_pip_tween() -> void:
	if _pip_tween != null and _pip_tween.is_valid():
		_pip_tween.kill()


func _sync_pip_colors() -> void:
	for i in pipe_parent.get_child_count():
		var pipe := pipe_parent.get_child(i) as ColorRect
		pipe.color = PIP_FILLED if i < _pips_shown else PIP_EMPTY


func _animate_pips(count: int) -> void:
	var growing := count > _pips_shown
	var from := mini(_pips_shown, count)
	var to := maxi(_pips_shown, count)

	var end_color := PIP_FILLED if growing else PIP_EMPTY
	_pips_shown = count

	_pip_tween = create_tween().set_parallel(true)

	for i in range(from, to):
		_animate_single_pip(i, from, to, growing, end_color)


func _animate_single_pip(index: int, from: int, to: int, growing: bool, end_color: Color) -> void:
	var pipe := pipe_parent.get_child(index) as ColorRect

	var step := index - from if growing else to - 1 - index
	var start := PIP_START_DELAY + step * PIP_STAGGER_SEC

	_pip_tween.tween_callback(
		func() -> void:
			pipe.color = PIP_FLASH,
	).set_delay(start)

	_pip_tween.tween_callback(
		func() -> void:
			pipe.color = end_color,
	).set_delay(start + PIP_FLASH_SEC)
