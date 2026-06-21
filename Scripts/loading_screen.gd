extends Node

const FADE_DURATION  := 0.25
const BAR_DURATION   := 0.55   # how long the bar takes to reach ~90%

const TIPS := [
	"Longer words score exponentially more points!",
	"Bomb tiles explode in a 3×3 area when used.",
	"Wild card tiles can match any letter in the alphabet.",
	"Building a combo streak multiplies your score.",
	"x2 and x3 tiles multiply your entire word score.",
	"Each word you find adds time back to the clock.",
	"Words over 4 letters earn a length bonus.",
	"Chain bomb explosions for massive points!",
	"Keep your combo streak alive for bigger rewards.",
	"Common letters appear more often — plan around them!",
	"The wild card ★ counts as any letter you need.",
	"Rare letters like Q, Z, and X are worth more in bombs.",
]

# ── Node references ───────────────────────────────────────────────────────────
var _canvas:    CanvasLayer
var _overlay:   ColorRect     # full-screen fade layer
var _card:      ColorRect     # centered content card
var _title:     Label
var _tip_tag:   Label
var _tip_body:  Label
var _bar_bg:    ColorRect
var _bar_fill:  ColorRect
var _bar_tween: Tween

func _ready() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 128
	add_child(_canvas)

	# ── Full-screen dark overlay (used for fade in/out) ───────────────────────
	_overlay = ColorRect.new()
	_overlay.color       = Color(0.04, 0.07, 0.16, 0.0)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.add_child(_overlay)

	# ── Centered card ─────────────────────────────────────────────────────────
	_card = ColorRect.new()
	_card.color          = Color(0.08, 0.12, 0.25, 0.96)
	_card.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_card.custom_minimum_size = Vector2(580, 400)
	# Anchor to center
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.offset_left  = -290
	_card.offset_right =  290
	_card.offset_top   = -200
	_card.offset_bottom =  200
	_card.modulate.a   = 0.0
	_canvas.add_child(_card)

	# ── Title label ───────────────────────────────────────────────────────────
	_title = Label.new()
	_title.text                  = "Wordmatician"
	_title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top  = 32
	_title.offset_bottom = 130
	_title.modulate.a  = 0.0
	var title_settings            = LabelSettings.new()
	title_settings.font           = load("res://Assets/Exo2-Bold.ttf")
	title_settings.font_size      = 72
	title_settings.font_color     = Color(1, 1, 1)
	title_settings.outline_size   = 7
	title_settings.outline_color  = Color(0.1, 0.15, 0.3, 0.9)
	title_settings.shadow_color   = Color(0, 0, 0, 0.45)
	title_settings.shadow_offset  = Vector2(3, 5)
	_title.label_settings         = title_settings
	_card.add_child(_title)

	# ── "TIP" tag ─────────────────────────────────────────────────────────────
	_tip_tag = Label.new()
	_tip_tag.text                 = "✦  TIP  ✦"
	_tip_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_tag.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tip_tag.offset_top    = 150
	_tip_tag.offset_bottom = 210
	_tip_tag.modulate.a    = 0.0
	var tag_settings               = LabelSettings.new()
	tag_settings.font              = load("res://Assets/Exo2-Bold.ttf")
	tag_settings.font_size         = 32
	tag_settings.font_color        = Color(0.6, 0.85, 1.0)
	tag_settings.outline_size      = 3
	tag_settings.outline_color     = Color(0.05, 0.1, 0.25, 0.8)
	_tip_tag.label_settings        = tag_settings
	_card.add_child(_tip_tag)

	# ── Tip body ──────────────────────────────────────────────────────────────
	_tip_body = Label.new()
	_tip_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_body.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	_tip_body.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	_tip_body.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_tip_body.offset_left   = 32
	_tip_body.offset_right  = -32
	_tip_body.offset_top    = 210
	_tip_body.offset_bottom = 330
	_tip_body.modulate.a    = 0.0
	var body_settings               = LabelSettings.new()
	body_settings.font              = load("res://Assets/Exo2-Regular.ttf")
	body_settings.font_size         = 38
	body_settings.font_color        = Color(0.85, 0.9, 1.0)
	body_settings.outline_size      = 3
	body_settings.outline_color     = Color(0.05, 0.1, 0.25, 0.7)
	_tip_body.label_settings        = body_settings
	_card.add_child(_tip_body)

	# ── Loading bar background ─────────────────────────────────────────────────
	_bar_bg = ColorRect.new()
	_bar_bg.color          = Color(0.05, 0.08, 0.18)
	_bar_bg.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	_bar_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bg.offset_left    = 40
	_bar_bg.offset_right   = -40
	_bar_bg.offset_top     = -52
	_bar_bg.offset_bottom  = -24
	_bar_bg.modulate.a     = 0.0
	_card.add_child(_bar_bg)

	# ── Loading bar fill ───────────────────────────────────────────────────────
	_bar_fill = ColorRect.new()
	_bar_fill.color        = Color(0.4, 0.75, 1.0)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Position inside bar_bg; sized relative to bar_bg at runtime
	_bar_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_bar_fill.offset_right = 0.0   # starts empty; animated in go_to()
	_bar_bg.add_child(_bar_fill)


func go_to(scene_path: String) -> void:
	# Pick a random tip
	_tip_body.text = TIPS[randi() % TIPS.size()]

	# Block all input while loading
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	# ── Fade everything in ────────────────────────────────────────────────────
	_bar_fill.size.x = 0.0
	var fade_in := create_tween().set_parallel(true)
	fade_in.tween_property(_overlay, "color:a",   0.85, FADE_DURATION).set_trans(Tween.TRANS_SINE)
	fade_in.tween_property(_card,    "modulate:a", 1.0,  FADE_DURATION).set_trans(Tween.TRANS_SINE)
	fade_in.tween_property(_title,   "modulate:a", 1.0,  FADE_DURATION).set_trans(Tween.TRANS_SINE)
	fade_in.tween_property(_tip_tag, "modulate:a", 1.0,  FADE_DURATION).set_trans(Tween.TRANS_SINE)
	fade_in.tween_property(_tip_body,"modulate:a", 1.0,  FADE_DURATION).set_trans(Tween.TRANS_SINE)
	fade_in.tween_property(_bar_bg,  "modulate:a", 1.0,  FADE_DURATION).set_trans(Tween.TRANS_SINE)
	await fade_in.finished

	# Bar width derived from card width (580) minus left+right offsets (40 each)
	var bar_width := 500.0

	# ── Animate bar to ~88% while scene loads ────────────────────────────────
	_bar_fill.size = Vector2(0.0, _bar_bg.size.y)
	if _bar_tween and _bar_tween.is_running():
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.tween_property(_bar_fill, "size:x", bar_width * 0.88, BAR_DURATION)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame

	# ── Snap bar to 100% ──────────────────────────────────────────────────────
	if _bar_tween and _bar_tween.is_running():
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.tween_property(_bar_fill, "size:x", bar_width, 0.15)\
		.set_trans(Tween.TRANS_SINE)
	await _bar_tween.finished

	await get_tree().create_timer(0.1).timeout

	# ── Fade everything out ───────────────────────────────────────────────────
	var fade_out := create_tween().set_parallel(true)
	fade_out.tween_property(_overlay, "color:a",   0.0, FADE_DURATION).set_trans(Tween.TRANS_SINE)
	fade_out.tween_property(_card,    "modulate:a", 0.0, FADE_DURATION).set_trans(Tween.TRANS_SINE)
	fade_out.tween_property(_title,   "modulate:a", 0.0, FADE_DURATION).set_trans(Tween.TRANS_SINE)
	fade_out.tween_property(_tip_tag, "modulate:a", 0.0, FADE_DURATION).set_trans(Tween.TRANS_SINE)
	fade_out.tween_property(_tip_body,"modulate:a", 0.0, FADE_DURATION).set_trans(Tween.TRANS_SINE)
	fade_out.tween_property(_bar_bg,  "modulate:a", 0.0, FADE_DURATION).set_trans(Tween.TRANS_SINE)
	await fade_out.finished

	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
