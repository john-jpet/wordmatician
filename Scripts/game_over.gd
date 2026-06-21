extends Control
const USE_MINIMAL_CARD := false

# Keep references alive as members (or use a Dictionary)
var lbl_score: Label
var lbl_best: Label
var lbl_words: Label
var lbl_longest: Label
var lbl_time: Label


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	modulate = Color(1, 1, 1, 1)
	z_index = 1024
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Force full viewport coverage when instanced under a Node2D parent
	# (anchor presets don't propagate correctly outside a Control hierarchy)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_add_home_button()

const INTRO_SCENE := "res://Scenes/intro.tscn"

func _add_home_button() -> void:
	var button := Button.new()
	button.text = "⌂"
	button.flat = true
	button.custom_minimum_size = Vector2(88, 88)
	button.size = Vector2(88, 88)
	button.pivot_offset = Vector2(44, 44)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.25, 0.85)
	style.corner_radius_top_left     = 20
	style.corner_radius_top_right    = 20
	style.corner_radius_bottom_left  = 20
	style.corner_radius_bottom_right = 20
	style.shadow_size  = 8
	style.shadow_color = Color(0, 0, 0, 0.4)
	button.add_theme_stylebox_override("normal", style)

	var style_hover := style.duplicate() as StyleBoxFlat
	style_hover.bg_color = style.bg_color.lightened(0.12)
	button.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := style.duplicate() as StyleBoxFlat
	style_pressed.bg_color = style.bg_color.darkened(0.1)
	button.add_theme_stylebox_override("pressed", style_pressed)

	button.add_theme_font_override("font", load("res://Assets/Exo2-Bold.ttf"))
	button.add_theme_font_size_override("font_size", 48)
	button.add_theme_color_override("font_color",       Color(0.85, 0.9, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0,  1.0, 1.0))

	var screen := get_viewport_rect().size
	button.position = Vector2(screen.x - button.size.x - 16, 16)
	button.z_index  = 1025

	button.pressed.connect(func(): LoadingScreen.go_to(INTRO_SCENE))
	add_child(button)

func _on_quit_pressed():
	LoadingScreen.go_to(INTRO_SCENE)

# Called by main.gd when the game ends — pass real stats here.
func setup(stats: Dictionary) -> void:
	visible = true
	if has_node("PanelRoot/Panel/VBox/StatsGrid"):
		# Fancy animated stats panel
		_populate_stats_into_existing(stats)
	elif has_node("ColorRect/VBoxContainer/FinalScoreLabel"):
		# Fallback: simple scene layout
		$ColorRect/VBoxContainer/FinalScoreLabel.text = "Score: %d" % stats.get("score", 0)


func populate_and_animate(grid: GridContainer, stats: Dictionary) -> void:
	lbl_score   = _add_stat_row(grid, "Score    ", str(stats.get("score", 0)), Color(0.7, 0.85, 1))
	lbl_best    = _add_stat_row(grid, "Best    ", str(stats.get("best", 0)))
	lbl_words   = _add_stat_row(grid, "Words Found    ", str(stats.get("words_found", 0)))
	lbl_longest = _add_stat_row(grid, "Longest Word    ", str(stats.get("longest_word", "-")))
	lbl_time    = _add_stat_row(grid, "Time    ", _format_time(float(stats.get("time", 0.0))))

	# Animate numeric ones (no lambdas!)
	_animate_number(lbl_score,  int(stats.get("score", 0)), 1.2)
	_animate_number(lbl_best,   int(stats.get("best", 0)),  1.2)
	_animate_number(lbl_words,  int(stats.get("words_found", 0)), 1.5)



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
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_override("font", load("res://Assets/Exo2-Bold.ttf"))
	btn.add_theme_font_size_override("font_size", 44)
	btn.add_theme_color_override("font_color",         Color(1, 1, 1))
	btn.add_theme_color_override("font_hover_color",   Color(1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.92, 1))
	btn.custom_minimum_size = Vector2(200, 80)

func _populate_stats_into_existing(stats: Dictionary) -> void:
	var grid: GridContainer = $PanelRoot/Panel/VBox/StatsGrid
	grid.columns = 2
	for c in grid.get_children():
		c.queue_free()

	populate_and_animate(grid, stats)

	if has_node("PanelRoot/Panel/VBox/Title"):
		$PanelRoot/Panel/VBox/Title.text = "TIME'S UP!"
	if has_node("PanelRoot/Panel/VBox/Subtitle"):
		$PanelRoot/Panel/VBox/Subtitle.text = "Well done!"

	var vbox: VBoxContainer = $PanelRoot/Panel/VBox
	var title: Label = $PanelRoot/Panel/VBox/Title
	var subtitle: Label = $PanelRoot/Panel/VBox/Subtitle
	var stats_grid: GridContainer = $PanelRoot/Panel/VBox/StatsGrid

	# Reorder to make sure title/subtitle are above
	vbox.move_child(title, 0)
	vbox.move_child(subtitle, 1)
	vbox.move_child(stats_grid, 2)

	# Style action buttons
	if has_node("PanelRoot/Panel/VBox/Buttons/TryAgain"):
		_style_button($PanelRoot/Panel/VBox/Buttons/TryAgain, true)
	if has_node("PanelRoot/Panel/VBox/Buttons/Quit"):
		_style_button($PanelRoot/Panel/VBox/Buttons/Quit, false)


func _make_btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 48)
	b.focus_mode = Control.FOCUS_NONE

	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.20, 0.25, 0.40)
	bs.corner_radius_top_left = 12
	bs.corner_radius_top_right = 12
	bs.corner_radius_bottom_left = 12
	bs.corner_radius_bottom_right = 12
	bs.shadow_size = 10
	bs.shadow_color = Color(0, 0, 0, 0.45)
	b.add_theme_stylebox_override("normal", bs)

	var bs_hover := bs.duplicate() as StyleBoxFlat
	bs_hover.bg_color = bs.bg_color.lightened(0.08)
	b.add_theme_stylebox_override("hover", bs_hover)

	var bs_pressed := bs.duplicate() as StyleBoxFlat
	bs_pressed.bg_color = bs.bg_color.darkened(0.1)
	b.add_theme_stylebox_override("pressed", bs_pressed)

	return b





func _add_stat_row(grid: GridContainer, label_text: String, value_text: String, value_color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = label_text
	var ls := LabelSettings.new()
	ls.font = preload("uid://6lcepanjvpbq")
	ls.font_size = 48
	l.label_settings = ls
	l.modulate = Color(1, 1, 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var v := Label.new()
	
	v.text = value_text
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.label_settings = ls
	v.modulate = value_color

	grid.add_child(l)
	grid.add_child(v)
	
	return v


func _format_time(s: float) -> String:
	var m := int(s) / 60
	var r := int(s) % 60
	return "%02d:%02d" % [m, r]
# Simple thousands-separator (e.g., 12,345). Remove if you don’t want commas.
func _format_with_commas(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3, 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
# Helper that formats and assigns the number every tween “tick”.
# value comes first (from tween), then bound args
func _set_number(value: float, label: Label, prefix: String = "", suffix: String = "") -> void:
	if !is_instance_valid(label): return
	var n := int(round(value))
	label.text = prefix + _format_with_commas(n) + suffix



func _animate_number(label: Label, target: int, duration: float = 0.8, prefix: String = "", suffix: String = "") -> void:
	if !is_instance_valid(label): return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# tween_method sends the animated value as the FIRST arg.
	tween.tween_method(Callable(self, "_set_number").bind(label, prefix, suffix), 0.0, float(target), duration)
