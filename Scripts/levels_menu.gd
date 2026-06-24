extends Control

const INTRO_SCENE := "res://Scenes/intro.tscn"
const LEVEL_SCENE := "res://Scenes/level.tscn"

const COLS    := 5
const BTN_SIZE := 118
const BTN_GAP  := 12

func _ready() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_add_home_button()
	_add_title()
	_add_level_grid()

# ── Title ─────────────────────────────────────────────────────────────────────

func _add_title() -> void:
	var lbl := Label.new()
	lbl.text = "LEVELS"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lbl.offset_top    = 32
	lbl.offset_bottom = 120
	var ls := LabelSettings.new()
	ls.font           = load("res://Assets/Exo2-Bold.ttf")
	ls.font_size      = 72
	ls.font_color     = Color(1, 1, 1)
	ls.outline_size   = 7
	ls.outline_color  = Color(0.1, 0.15, 0.3, 0.9)
	ls.shadow_color   = Color(0, 0, 0, 0.45)
	ls.shadow_offset  = Vector2(3, 5)
	lbl.label_settings = ls
	add_child(lbl)

# ── Home button ───────────────────────────────────────────────────────────────

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
	var sh := style.duplicate() as StyleBoxFlat
	sh.bg_color = style.bg_color.lightened(0.12)
	button.add_theme_stylebox_override("hover", sh)
	var sp := style.duplicate() as StyleBoxFlat
	sp.bg_color = style.bg_color.darkened(0.1)
	button.add_theme_stylebox_override("pressed", sp)

	button.add_theme_font_override("font", load("res://Assets/Exo2-Bold.ttf"))
	button.add_theme_font_size_override("font_size", 48)
	button.add_theme_color_override("font_color",       Color(0.85, 0.9, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0,  1.0, 1.0))

	var screen := get_viewport_rect().size
	button.position = Vector2(screen.x - button.size.x - 16, 16)
	button.z_index  = 10

	button.pressed.connect(func(): LoadingScreen.go_to(INTRO_SCENE))
	add_child(button)

# ── Level grid ────────────────────────────────────────────────────────────────

func _add_level_grid() -> void:
	var screen    := get_viewport_rect().size
	var total_w   := COLS * BTN_SIZE + (COLS - 1) * BTN_GAP
	var start_x   := (screen.x - total_w) / 2.0
	var start_y   := 156.0

	for i in LevelsData.LEVELS.size():
		var col := i % COLS
		var row := i / COLS
		var btn: TextureButton = _make_level_button(i)
		btn.position = Vector2(
			start_x + col * (BTN_SIZE + BTN_GAP),
			start_y + row * (BTN_SIZE + BTN_GAP)
		)
		add_child(btn)

func _make_level_button(idx: int) -> TextureButton:
	var is_star := LevelsManager.is_star(idx)
	var done    := LevelsManager.is_completed(idx)

	var tile_tex: String
	if is_star:
		tile_tex = "res://Assets/amethysttile.png"
	elif done:
		tile_tex = "res://Assets/goldtile.png"
	else:
		tile_tex = "res://Assets/basetile.png"

	var btn := TextureButton.new()
	btn.texture_normal  = load(tile_tex)
	btn.texture_hover   = btn.texture_normal
	btn.texture_pressed = btn.texture_normal
	btn.stretch_mode    = TextureButton.STRETCH_SCALE
	btn.custom_minimum_size = Vector2(BTN_SIZE, BTN_SIZE)
	btn.size                = Vector2(BTN_SIZE, BTN_SIZE)
	btn.pivot_offset        = Vector2(BTN_SIZE / 2.0, BTN_SIZE / 2.0)
	btn.focus_mode          = Control.FOCUS_NONE

	var lbl := Label.new()
	lbl.text                 = str(idx + 1)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	var ls               := LabelSettings.new()
	ls.font              = load("res://Assets/Exo2-Bold.ttf")
	ls.font_size         = 38
	ls.font_color        = Color(1, 1, 1)
	ls.outline_size      = 6
	ls.outline_color     = Color(0.1, 0.2, 0.4, 0.5)
	ls.shadow_color      = Color(0, 0, 0, 0.35)
	ls.shadow_offset     = Vector2(2, 3)
	lbl.label_settings   = ls
	btn.add_child(lbl)

	btn.pressed.connect(func():
		LevelsManager.current_level_idx = idx
		LoadingScreen.go_to(LEVEL_SCENE)
	)
	return btn
