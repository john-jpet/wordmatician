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
	_add_help_button()
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

	button.pressed.connect(func(): AudioManager.play("select"); LoadingScreen.go_to(INTRO_SCENE))
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
		AudioManager.play("select")
		LevelsManager.current_level_idx = idx
		LoadingScreen.go_to(LEVEL_SCENE)
	)
	return btn

# ── Help button & tooltip ─────────────────────────────────────────────────────

func _add_help_button() -> void:
	var button := Button.new()
	button.text = "?"
	button.flat = true
	button.custom_minimum_size = Vector2(72, 72)
	button.size                = Vector2(72, 72)
	button.pivot_offset        = Vector2(36, 36)

	var style := StyleBoxFlat.new()
	style.bg_color                   = Color(0.08, 0.12, 0.25, 0.85)
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
	button.add_theme_font_size_override("font_size", 36)
	button.add_theme_color_override("font_color",       Color(0.85, 0.9, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0,  1.0, 1.0))

	# Top-left, beside home button
	button.position = Vector2(16, 16)

	button.pressed.connect(_show_help_popup)
	add_child(button)

func _show_help_popup() -> void:
	AudioManager.play("select")

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 20
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)

	var screen  := get_viewport_rect().size
	var card_w  := 560.0
	var card_h  := 580.0
	var card    := ColorRect.new()
	card.color    = Color(0.08, 0.12, 0.25, 0.97)
	card.position = Vector2((screen.x - card_w) / 2.0, (screen.y - card_h) / 2.0)
	card.size     = Vector2(card_w, card_h)
	overlay.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(36, 36)
	vbox.size     = Vector2(card_w - 72, card_h - 72)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	card.add_child(vbox)

	var bold    = load("res://Assets/Exo2-Bold.ttf")
	var regular = load("res://Assets/Exo2-Regular.ttf")

	var _add_text := func(text: String, font: FontFile, size: int, color: Color) -> void:
		var lbl := Label.new()
		lbl.text                 = text
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
		var ls              := LabelSettings.new()
		ls.font              = font
		ls.font_size         = size
		ls.font_color        = color
		ls.outline_size      = 3
		ls.outline_color     = Color(0.05, 0.1, 0.25, 0.7)
		lbl.label_settings   = ls
		vbox.add_child(lbl)

	_add_text.call("How to Play", bold, 52, Color(1, 1, 1))

	_add_text.call(
		"Your only goal is to clear the board!",
		regular, 34, Color(0.85, 0.9, 1.0))

	var divider := ColorRect.new()
	divider.color = Color(0.3, 0.45, 0.7, 0.4)
	divider.custom_minimum_size = Vector2(card_w - 72, 2)
	vbox.add_child(divider)

	_add_text.call("Bonus: ★", bold, 40, Color(1.0, 0.85, 0.2))
	_add_text.call(
		"Every level has a unique theme.\nFind all of the theme words for a bonus!",
		regular, 34, Color(0.85, 0.9, 1.0))

	var close_btn := Button.new()
	close_btn.text       = "GOT IT"
	close_btn.flat       = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.18, 0.32, 0.68, 0.95)
	cs.corner_radius_top_left     = 20
	cs.corner_radius_top_right    = 20
	cs.corner_radius_bottom_left  = 20
	cs.corner_radius_bottom_right = 20
	cs.shadow_size = 8
	cs.shadow_color = Color(0, 0, 0, 0.4)
	cs.content_margin_left = 28
	cs.content_margin_right = 28
	cs.content_margin_top = 14
	cs.content_margin_bottom = 14
	close_btn.add_theme_stylebox_override("normal", cs)
	var csh := cs.duplicate() as StyleBoxFlat
	csh.bg_color = cs.bg_color.lightened(0.12)
	close_btn.add_theme_stylebox_override("hover", csh)
	close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close_btn.add_theme_font_override("font", bold)
	close_btn.add_theme_font_size_override("font_size", 38)
	close_btn.add_theme_color_override("font_color",       Color(1, 1, 1))
	close_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	close_btn.pressed.connect(func(): AudioManager.play("select"); overlay.queue_free())
	vbox.add_child(close_btn)

	card.modulate.a  = 0.0
	overlay.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(overlay, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(card,    "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
