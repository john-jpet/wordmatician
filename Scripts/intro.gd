extends Control

const MAIN_SCENE  := "res://Scenes/main.tscn"
const DAILY_SCENE := "res://Scenes/daily.tscn"

@onready var play_button    := $VBox/PlayButton
@onready var daily_button   := $VBox/DailyButton
@onready var title_label    := $VBox/TitleLabel
@onready var subtitle_label := $VBox/SubtitleLabel

var _stats_panel: Control

func _style_button(btn: Button, accent := false) -> void:
	var base_col := Color(0.18, 0.32, 0.68, 0.95) if accent else Color(0.12, 0.20, 0.48, 0.92)
	var style := StyleBoxFlat.new()
	style.bg_color                   = base_col
	style.corner_radius_top_left     = 22
	style.corner_radius_top_right    = 22
	style.corner_radius_bottom_left  = 22
	style.corner_radius_bottom_right = 22
	style.shadow_size                = 10
	style.shadow_color               = Color(0, 0, 0, 0.4)
	style.content_margin_left        = 28
	style.content_margin_right       = 28
	style.content_margin_top         = 14
	style.content_margin_bottom      = 14
	btn.add_theme_stylebox_override("normal", style)
	var sh := style.duplicate() as StyleBoxFlat
	sh.bg_color = base_col.lightened(0.12)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := style.duplicate() as StyleBoxFlat
	sp.bg_color = base_col.darkened(0.12)
	btn.add_theme_stylebox_override("pressed", sp)
	var sf := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("focus", sf)
	btn.add_theme_font_override("font", load("res://Assets/Exo2-Bold.ttf"))
	btn.add_theme_font_size_override("font_size", 48)
	btn.add_theme_color_override("font_color",         Color(1, 1, 1))
	btn.add_theme_color_override("font_hover_color",   Color(1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.92, 1))

func _ready():
	position = Vector2.ZERO
	size = get_viewport_rect().size

	title_label.modulate.a    = 0.0
	subtitle_label.modulate.a = 0.0
	play_button.modulate.a    = 0.0
	daily_button.modulate.a   = 0.0

	play_button.custom_minimum_size  = Vector2(340, 90)
	daily_button.custom_minimum_size = Vector2(340, 90)
	_style_button(play_button,  true)
	_style_button(daily_button, false)

	$VBox/Spacer.custom_minimum_size = Vector2(0, 120)

	$VBox.add_theme_constant_override("separation", 20)

	_build_stats_panel()

	var levels_btn := Button.new()
	levels_btn.text = "LEVELS"
	levels_btn.custom_minimum_size   = Vector2(340, 90)
	levels_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	levels_btn.modulate.a = 0.0
	levels_btn.pressed.connect(func(): LoadingScreen.go_to("res://Scenes/levels_menu.tscn"))
	_style_button(levels_btn, false)
	$VBox.add_child(levels_btn)

	var stats_btn := Button.new()
	stats_btn.text = "STATS"
	stats_btn.custom_minimum_size   = Vector2(340, 90)
	stats_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stats_btn.modulate.a = 0.0
	stats_btn.pressed.connect(_on_stats_pressed)
	_style_button(stats_btn, false)
	$VBox.add_child(stats_btn)

	var tween := create_tween().set_parallel(false)
	tween.tween_property(title_label,    "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(subtitle_label, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(play_button,    "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(daily_button,   "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(levels_btn,     "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(stats_btn,      "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)


# ── Stats panel ───────────────────────────────────────────────────────────────

func _build_stats_panel() -> void:
	# Full-screen dim
	_stats_panel = Control.new()
	_stats_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stats_panel.visible = false
	_stats_panel.z_index = 20
	add_child(_stats_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_stats_panel.add_child(dim)

	# Card
	var card := ColorRect.new()
	card.color = Color(0.08, 0.12, 0.25, 0.97)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.custom_minimum_size = Vector2(580, 780)
	card.offset_left   = -290
	card.offset_right  =  290
	card.offset_top    = -390
	card.offset_bottom =  390
	_stats_panel.add_child(card)

	# Title inside card
	var heading := Label.new()
	heading.text                = "STATS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.set_anchors_preset(Control.PRESET_TOP_WIDE)
	heading.offset_top    = 32
	heading.offset_bottom = 110
	var h_settings               = LabelSettings.new()
	h_settings.font              = load("res://Assets/Exo2-Bold.ttf")
	h_settings.font_size         = 72
	h_settings.font_color        = Color(1, 1, 1)
	h_settings.outline_size      = 7
	h_settings.outline_color     = Color(0.1, 0.15, 0.3, 0.9)
	h_settings.shadow_color      = Color(0, 0, 0, 0.45)
	h_settings.shadow_offset     = Vector2(3, 5)
	heading.label_settings       = h_settings
	card.add_child(heading)

	# Divider
	var div := ColorRect.new()
	div.color = Color(0.3, 0.45, 0.7, 0.5)
	div.set_anchors_preset(Control.PRESET_TOP_WIDE)
	div.offset_left   = 40
	div.offset_right  = -40
	div.offset_top    = 118
	div.offset_bottom = 122
	card.add_child(div)

	# Stats rows
	var rows := [
		["High Score",         str(StatsManager.data["high_score"])],
		["Games Played",       str(StatsManager.data["games_played"])],
		["Total Words Found",  str(StatsManager.data["total_words"])],
		["Longest Word",       _longest_display()],
		["Daily Puzzles",      str(StatsManager.data["daily_cleared"])],
		["Levels Cleared",     str(LevelsManager.completed.size()) + " / " + str(LevelsData.LEVELS.size())],
	]

	var row_font_bold    = load("res://Assets/Exo2-Bold.ttf")
	var row_font_regular = load("res://Assets/Exo2-Regular.ttf")

	for i in rows.size():
		var y_top := 140 + i * 98

		var lbl := Label.new()
		lbl.text                = rows[i][0]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
		lbl.offset_left   = 48
		lbl.offset_right  = -48
		lbl.offset_top    = y_top
		lbl.offset_bottom = y_top + 88
		var ls               = LabelSettings.new()
		ls.font              = row_font_regular
		ls.font_size         = 38
		ls.font_color        = Color(0.75, 0.82, 1.0)
		ls.outline_size      = 3
		ls.outline_color     = Color(0.05, 0.1, 0.25, 0.7)
		lbl.label_settings   = ls
		card.add_child(lbl)

		var val := Label.new()
		val.text                = rows[i][1]
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.set_anchors_preset(Control.PRESET_TOP_WIDE)
		val.offset_left   = 48
		val.offset_right  = -48
		val.offset_top    = y_top
		val.offset_bottom = y_top + 88
		var vs               = LabelSettings.new()
		vs.font              = row_font_bold
		vs.font_size         = 42
		vs.font_color        = Color(1, 1, 1)
		vs.outline_size      = 4
		vs.outline_color     = Color(0.05, 0.1, 0.25, 0.8)
		val.label_settings   = vs
		card.add_child(val)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.flat = true
	close_btn.custom_minimum_size = Vector2(200, 72)
	close_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	close_btn.offset_left   = 190
	close_btn.offset_right  = -190
	close_btn.offset_top    = -88
	close_btn.offset_bottom = -16

	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.15, 0.22, 0.42, 0.9)
	cs.corner_radius_top_left     = 16
	cs.corner_radius_top_right    = 16
	cs.corner_radius_bottom_left  = 16
	cs.corner_radius_bottom_right = 16
	cs.shadow_size  = 6
	cs.shadow_color = Color(0, 0, 0, 0.35)
	close_btn.add_theme_stylebox_override("normal", cs)
	var cs_hover := cs.duplicate() as StyleBoxFlat
	cs_hover.bg_color = cs.bg_color.lightened(0.1)
	close_btn.add_theme_stylebox_override("hover", cs_hover)

	close_btn.add_theme_font_override("font", load("res://Assets/Exo2-Bold.ttf"))
	close_btn.add_theme_font_size_override("font_size", 36)
	close_btn.add_theme_color_override("font_color",       Color(0.85, 0.9, 1.0))
	close_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

	close_btn.pressed.connect(_on_stats_closed)
	card.add_child(close_btn)


func _longest_display() -> String:
	var w: String = String(StatsManager.data["longest_word"])
	return w if w != "" else "-"


# ── Handlers ──────────────────────────────────────────────────────────────────

func _on_stats_pressed() -> void:
	_stats_panel.visible = true
	_stats_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_stats_panel, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)

func _on_stats_closed() -> void:
	var tw := create_tween()
	tw.tween_property(_stats_panel, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): _stats_panel.visible = false)

func _on_play_pressed():
	LoadingScreen.go_to(MAIN_SCENE)

func _on_daily_pressed():
	LoadingScreen.go_to(DAILY_SCENE)
