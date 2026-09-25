# THIS need an update fr
extends Node

const SKIN_ROOT := "res://skin"
const USER_SKIN_ROOT := "user://skin"
const FALLBACK_SKIN := "default_skin"

# Logical name -> file in the skin folder.
const FILE_MAP := {
	"cursor_sprite": "cursor.png",
	"beat_point_bg": "beat_point_bg.png",
	"beat_point_outline": "beat_point_outline.png",
	"beat_receptor": "beat_receptor.png",
	"beat_receptor_clicked": "beat_receptor_clicked.png",
}

# Kept for backwards compat — use current_skin / FALLBACK_SKIN instead.
var fallback_skin := FALLBACK_SKIN
var current_skin := FALLBACK_SKIN

var cursor_sprite: Texture2D
var beat_point_bg: Texture2D
var beat_point_outline: Texture2D
var beat_receptor: Texture2D
var beat_receptor_clicked: Texture2D


func _ready() -> void:
	load_skin()


func reload(skin_name: String) -> bool:
	fallback_skin = (
		skin_name.strip_edges() if not skin_name.strip_edges().is_empty() else FALLBACK_SKIN
	)
	return load_skin()


func load_skin() -> bool:
	# var requested := skin_name.strip_edges()
	# if requested.is_empty():

	var requested = fallback_skin
	current_skin = requested

	var ok := true
	for key in FILE_MAP:
		var tex := _try_load(requested, String(FILE_MAP[key]))
		set(key, tex)
		if tex == null:
			ok = false
	return ok


func get_texture(key: String) -> Texture2D:
	return get(key) as Texture2D


func is_fully_loaded() -> bool:
	for key in FILE_MAP:
		if get(key) == null:
			return false
	return true


func apply_to_beat_point(beat_point: Sprite2D) -> void:
	# beat_point.tscn layout: root Sprite2D (bg) + child "CircleOutline".
	if beat_point_bg != null:
		beat_point.texture = beat_point_bg
	var outline := beat_point.get_node_or_null("CircleOutline")
	if outline is Sprite2D and beat_point_outline != null:
		(outline as Sprite2D).texture = beat_point_outline


func apply_to_receptor(receptor: Sprite2D) -> void:
	# game.tscn layout: beat_receptor (Sprite2D) + child "clicked".
	if beat_receptor != null:
		receptor.texture = beat_receptor
	var clicked := receptor.get_node_or_null("clicked")
	if clicked is Sprite2D and beat_receptor_clicked != null:
		(clicked as Sprite2D).texture = beat_receptor_clicked


func apply_to_cursor(cursor: Sprite2D) -> void:
	if cursor_sprite != null:
		cursor.texture = cursor_sprite


func _try_load(skin_name: String, file_name: String) -> Texture2D:
	# Try requested skin first, then fall back to default_skin.
	var primary := "%s/%s/%s" % [SKIN_ROOT, skin_name, file_name]
	if ResourceLoader.exists(primary):
		var tex := ResourceLoader.load(primary) as Texture2D
		if tex != null:
			return tex
		push_warning("SkinManager: '%s' exists but is not a Texture2D." % primary)

	if skin_name != FALLBACK_SKIN:
		var fallback := "%s/%s/%s" % [SKIN_ROOT, FALLBACK_SKIN, file_name]
		if ResourceLoader.exists(fallback):
			var fallback_tex := ResourceLoader.load(fallback) as Texture2D
			if fallback_tex != null:
				return fallback_tex

	push_error("SkinManager: missing '%s' in skin '%s' (and no fallback)." % [file_name, skin_name])
	return null
