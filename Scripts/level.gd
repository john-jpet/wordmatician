extends Node2D

const INTRO_SCENE       := "res://Scenes/intro.tscn"
const LEVELS_MENU_SCENE := "res://Scenes/levels_menu.tscn"
const LEVEL_SCENE       := "res://Scenes/level.tscn"

var tile_scene := preload("res://Scenes/letter_tile.tscn")

@onready var grid_node          := $Grid
@onready var current_word_label := $UI/CurrentWordLabel
@onready var level_label        := $UI/LevelLabel

const GRID_SIZE := 5
const TILE_SIZE := 128
const TILE_GAP  := 12

var board:               Array      = []
var selected_letters:    Array      = []
var dictionary:          Dictionary = {}
var level_words:         Array      = []   # intended words (hint + star tracking)
var intended_words_set:  Dictionary = {}   # word -> true, O(1) lookup
var tiles_remaining:     int        = 25
var non_intended_count:  int        = 0    # >0 means only checkmark possible
var input_blocked:       bool       = false

# ── Entry point ───────────────────────────────────────────────────────────────

func _ready() -> void:
	load_dictionary()

	var idx  := LevelsManager.current_level_idx
	var data: Dictionary = LevelsData.LEVELS[idx]
	level_words = Array(data["words"])
	level_label.text = "%s  ·  Level %d" % [data["theme"], idx + 1]

	# Build intended word lookup set
	intended_words_set.clear()
	for w in level_words:
		intended_words_set[String(w).to_upper()] = true

	_center_grid()
	_spawn_grid(_flatten_and_shuffle(level_words))

	_add_home_button()
	_add_submit_button()
	_add_cancel_button()
	_add_hint_button()
	_add_restart_button()
	_block_input_briefly()

# ── Grid ──────────────────────────────────────────────────────────────────────

func _center_grid() -> void:
	var screen  := get_viewport().get_visible_rect().size
	var grid_px := Vector2(
		GRID_SIZE * TILE_SIZE + (GRID_SIZE - 1) * TILE_GAP,
		GRID_SIZE * TILE_SIZE + (GRID_SIZE - 1) * TILE_GAP
	)
	grid_node.position = Vector2(
		(screen.x - grid_px.x) / 2.0 + TILE_SIZE / 2.0,
		(screen.y - grid_px.y) / 2.0
	)

func _flatten_and_shuffle(words: Array) -> Array:
	var letters: Array = []
	for w in words:
		var ws: String = String(w)
		for i in ws.length():
			letters.append(ws[i])
	letters.shuffle()
	return letters

func _spawn_grid(letters: Array) -> void:
	for child in grid_node.get_children():
		child.queue_free()
	board.clear()
	tiles_remaining = 25

	for y in range(GRID_SIZE):
		var row: Array = []
		for x in range(GRID_SIZE):
			var letter: String = letters[y * GRID_SIZE + x]
			var tile = tile_scene.instantiate()
			tile.set_letter(letter, "none")
			tile.grid_pos = Vector2i(x, y)
			var target := Vector2(x * (TILE_SIZE + TILE_GAP), y * (TILE_SIZE + TILE_GAP))
			tile.position = Vector2(target.x, -TILE_SIZE * (GRID_SIZE + 1))
			tile.modulate.a = 0.0
			grid_node.add_child(tile)
			row.append(tile)

			var delay := x * 0.06 + y * 0.03
			var tw := create_tween()
			tw.tween_interval(delay)
			tw.tween_property(tile, "modulate:a", 1.0, 0.05)
			tw.parallel().tween_property(tile, "position", target, 0.45) \
				.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		board.append(row)

func _drop_tiles() -> void:
	for x in range(GRID_SIZE):
		var empty_y := GRID_SIZE - 1
		for y in range(GRID_SIZE - 1, -1, -1):
			if board[y][x] != null:
				if y != empty_y:
					var tile: Node2D = board[y][x]
					board[empty_y][x] = tile
					board[y][x] = null
					tile.grid_pos = Vector2i(x, empty_y)
					var target := Vector2(x * (TILE_SIZE + TILE_GAP), empty_y * (TILE_SIZE + TILE_GAP))
					var tw := create_tween()
					tw.tween_property(tile, "position", target, 0.2).set_trans(Tween.TRANS_LINEAR)
					var squash := create_tween()
					squash.tween_interval(0.2)
					squash.tween_property(tile, "scale", Vector2(1.1, 0.9), 0.05)
					squash.tween_property(tile, "scale", Vector2(1.0, 1.0), 0.05)
				empty_y -= 1

func _block_input_briefly() -> void:
	input_blocked = true
	get_tree().create_timer(0.75).timeout.connect(func(): input_blocked = false)

# ── Input / selection ─────────────────────────────────────────────────────────

func letter_tapped(tile) -> void:
	if input_blocked:
		return
	if tile in selected_letters:
		selected_letters.erase(tile)
		tile.modulate = Color(1, 1, 1)
	else:
		selected_letters.append(tile)
		tile.modulate = Color(0.7, 0.7, 1)
		AudioManager.play("select")
	_update_word_label()

func _update_word_label() -> void:
	var w := ""
	for t in selected_letters:
		w += t.letter
	current_word_label.text = w

# ── Word checking ─────────────────────────────────────────────────────────────

func _on_submit_pressed() -> void:
	_check_word()

func _on_cancel_pressed() -> void:
	for t in selected_letters:
		if is_instance_valid(t):
			t.modulate = Color(1, 1, 1)
	selected_letters.clear()
	current_word_label.text = ""

func _check_word() -> void:
	if input_blocked or selected_letters.size() < 3:
		return

	var word := ""
	for t in selected_letters:
		word += t.letter
	word = word.to_upper()

	if not dictionary.has(word):
		_invalid_feedback()
		return

	var is_intended := intended_words_set.has(word)
	if is_intended:
		intended_words_set.erase(word)  # each intended word only counts once
	else:
		non_intended_count += 1
		AudioManager.play("word_found")

	input_blocked = true
	var tiles_to_remove := selected_letters.duplicate()
	selected_letters.clear()
	current_word_label.text = ""

	if is_intended:
		_remove_tiles_intended(tiles_to_remove)
	else:
		_remove_tiles_normal(tiles_to_remove)

	tiles_remaining -= tiles_to_remove.size()

	await get_tree().create_timer(0.25).timeout
	_drop_tiles()
	input_blocked = false

	if tiles_remaining <= 0:
		_on_level_complete()

func _remove_tiles_normal(tiles: Array) -> void:
	for t in tiles:
		if is_instance_valid(t):
			board[t.grid_pos.y][t.grid_pos.x] = null
			var tw := create_tween()
			tw.tween_property(t, "scale",      Vector2(1.4, 1.4), 0.1)
			tw.tween_property(t, "modulate:a", 0.0,               0.2)
			tw.tween_callback(func(): if is_instance_valid(t): t.queue_free())

func _remove_tiles_intended(tiles: Array) -> void:
	AudioManager.play("feature_word")
	# Green flash animation
	for t in tiles:
		if is_instance_valid(t):
			board[t.grid_pos.y][t.grid_pos.x] = null
			var tw := create_tween()
			tw.tween_property(t, "modulate", Color(0.4, 1.0, 0.55), 0.08).set_trans(Tween.TRANS_SINE)
			tw.tween_property(t, "scale",    Vector2(1.5, 1.5),      0.12)
			tw.tween_property(t, "modulate:a", 0.0,                  0.22)
			tw.tween_callback(func(): if is_instance_valid(t): t.queue_free())
	_show_theme_word_popup()

func _invalid_feedback() -> void:
	AudioManager.play("mistake")
	for t in selected_letters:
		var tw   := create_tween()
		var orig := Vector2(t.position)
		tw.tween_property(t, "modulate",               Color(1, 0.3, 0.3), 0.05)
		tw.tween_property(t, "position", orig + Vector2(5, 0),             0.05)
		tw.tween_property(t, "position", orig - Vector2(5, 0),             0.05)
		tw.tween_property(t, "position", orig,                             0.05)
		tw.tween_property(t, "modulate",               Color(1, 1, 1),     0.05)
	for t in selected_letters:
		t.modulate = Color(1, 1, 1)
	selected_letters.clear()
	current_word_label.text = ""

# ── Theme word popup ──────────────────────────────────────────────────────────

func _show_theme_word_popup() -> void:
	var popup := Label.new()
	popup.text                 = "Theme word!"
	popup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	popup.size                 = Vector2(720, 64)

	var screen := get_viewport_rect().size
	popup.position = Vector2(0, screen.y / 2.0 - 180)

	var ls              := LabelSettings.new()
	ls.font              = load("res://Assets/Exo2-Bold.ttf")
	ls.font_size         = 48
	ls.font_color        = Color(0.4, 1.0, 0.55)
	ls.outline_size      = 5
	ls.outline_color     = Color(0.05, 0.25, 0.1, 0.85)
	ls.shadow_color      = Color(0, 0, 0, 0.4)
	ls.shadow_offset     = Vector2(2, 3)
	popup.label_settings = ls
	popup.modulate.a     = 0.0
	$UI.add_child(popup)

	var tw := create_tween()
	tw.tween_property(popup, "modulate:a",  1.0, 0.15).set_trans(Tween.TRANS_SINE)
	tw.tween_property(popup, "position:y",  popup.position.y - 55, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(popup, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_delay(0.35)
	tw.tween_callback(func(): if is_instance_valid(popup): popup.queue_free())

# ── Hint ──────────────────────────────────────────────────────────────────────

func _board_letter_counts() -> Dictionary:
	var counts := {}
	for row in board:
		for tile in row:
			if tile != null and is_instance_valid(tile):
				var L: String = tile.letter.to_upper()
				counts[L] = counts.get(L, 0) + 1
	return counts

func _find_hintable_word() -> String:
	var available := _board_letter_counts()
	var candidates := level_words.duplicate()
	candidates.shuffle()
	for word in candidates:
		var w: String = String(word).to_upper()
		var need := {}
		for i in w.length():
			var ch: String = w[i]
			need[ch] = need.get(ch, 0) + 1
		var ok := true
		for ch in need:
			if available.get(ch, 0) < need[ch]:
				ok = false
				break
		if ok:
			return w
	return ""

func _on_hint_pressed() -> void:
	if input_blocked:
		return
	var word := _find_hintable_word()
	if word == "":
		return

	var need := {}
	for i in word.length():
		var ch: String = word[i]
		need[ch] = need.get(ch, 0) + 1

	var hint_tiles: Array = []
	for row in board:
		for tile in row:
			if tile == null or not is_instance_valid(tile):
				continue
			var L: String = tile.letter.to_upper()
			if need.get(L, 0) > 0:
				hint_tiles.append(tile)
				need[L] -= 1

	for tile in hint_tiles:
		var tw := create_tween()
		tw.tween_property(tile, "modulate", Color(1, 0.85, 0.2), 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(tile, "modulate", Color(1, 1,    1),   0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(tile, "modulate", Color(1, 0.85, 0.2), 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(tile, "modulate", Color(1, 1,    1),   0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(tile, "modulate", Color(1, 0.85, 0.2), 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(tile, "modulate", Color(1, 1,    1),   0.25).set_trans(Tween.TRANS_SINE)

# ── Win ───────────────────────────────────────────────────────────────────────

func _on_level_complete() -> void:
	var idx      := LevelsManager.current_level_idx
	var earned_star := non_intended_count == 0
	AudioManager.play("fanfare")

	if earned_star:
		LevelsManager.record_star(idx)
	else:
		LevelsManager.record_completion(idx)

	input_blocked = true
	_hide_gameplay_buttons()

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.78)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 50
	$UI.add_child(overlay)

	var screen := get_viewport_rect().size
	var card_w := 520.0
	var card_h := 560.0
	var card   := ColorRect.new()
	card.color    = Color(0.08, 0.12, 0.25, 0.97)
	card.position = Vector2((screen.x - card_w) / 2.0, (screen.y - card_h) / 2.0)
	card.size     = Vector2(card_w, card_h)
	overlay.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.position  = Vector2(32, 32)
	vbox.size      = Vector2(card_w - 64, card_h - 64)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	card.add_child(vbox)

	# Title
	var title := Label.new()
	title.text                = "Level Complete!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ts               := LabelSettings.new()
	ts.font              = load("res://Assets/Exo2-Bold.ttf")
	ts.font_size         = 56
	ts.font_color        = Color(1, 1, 1)
	ts.outline_size      = 6
	ts.outline_color     = Color(0.1, 0.15, 0.3, 0.9)
	ts.shadow_color      = Color(0, 0, 0, 0.4)
	ts.shadow_offset     = Vector2(3, 5)
	title.label_settings = ts
	vbox.add_child(title)

	# Badge
	var badge := Label.new()
	badge.text                = "★" if earned_star else "✓"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bs               := LabelSettings.new()
	bs.font              = load("res://Assets/Exo2-Bold.ttf")
	bs.font_size         = 72
	bs.font_color        = Color(1.0, 0.85, 0.2) if earned_star else Color(0.75, 0.86, 1.0)
	bs.outline_size      = 5
	bs.outline_color     = Color(0.1, 0.15, 0.3, 0.8)
	badge.label_settings = bs
	vbox.add_child(badge)

	# Star message
	if earned_star:
		var msg := Label.new()
		msg.text                = "All theme words found!"
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		msg.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
		var ms               := LabelSettings.new()
		ms.font              = load("res://Assets/Exo2-Regular.ttf")
		ms.font_size         = 34
		ms.font_color        = Color(0.85, 0.9, 1.0)
		ms.outline_size      = 3
		ms.outline_color     = Color(0.05, 0.1, 0.25, 0.7)
		msg.label_settings   = ms
		vbox.add_child(msg)

	# Buttons
	if not earned_star:
		var replay_btn := _make_overlay_button("PLAY AGAIN", false)
		replay_btn.pressed.connect(func(): AudioManager.play("select"); _restart_level())
		vbox.add_child(replay_btn)

	if idx + 1 < LevelsData.LEVELS.size():
		var next_btn := _make_overlay_button("NEXT LEVEL", true)
		next_btn.pressed.connect(func():
			AudioManager.play("select")
			LevelsManager.current_level_idx = idx + 1
			LoadingScreen.go_to(LEVEL_SCENE)
		)
		vbox.add_child(next_btn)

	var menu_btn := _make_overlay_button("LEVELS MENU", false)
	menu_btn.pressed.connect(func(): AudioManager.play("select"); LoadingScreen.go_to(LEVELS_MENU_SCENE))
	vbox.add_child(menu_btn)

	card.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)

func _make_overlay_button(label: String, accent: bool) -> Button:
	var base_col := Color(0.18, 0.32, 0.68, 0.95) if accent else Color(0.12, 0.20, 0.48, 0.92)
	var btn := Button.new()
	btn.text       = label
	btn.flat       = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(300, 72)

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
	btn.add_theme_font_size_override("font_size", 40)
	btn.add_theme_color_override("font_color",         Color(1, 1, 1))
	btn.add_theme_color_override("font_hover_color",   Color(1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.92, 1))
	return btn

# ── Restart ───────────────────────────────────────────────────────────────────

func _restart_level() -> void:
	# Remove win overlay if present
	for child in $UI.get_children():
		if child is ColorRect and child.z_index == 50:
			child.queue_free()

	for grid_child in grid_node.get_children():
		grid_child.queue_free()
	board.clear()
	selected_letters.clear()
	current_word_label.text = ""

	# Reset tracking
	non_intended_count = 0
	intended_words_set.clear()
	for w in level_words:
		intended_words_set[String(w).to_upper()] = true

	_show_gameplay_buttons()
	_spawn_grid(_flatten_and_shuffle(level_words))
	_block_input_briefly()

func _on_restart_pressed() -> void:
	AudioManager.play("select")
	_restart_level()

# ── Buttons ───────────────────────────────────────────────────────────────────

func _hide_gameplay_buttons() -> void:
	for btn_name in ["SubmitButton", "CancelButton", "HintButton", "RestartButton"]:
		var node := $UI.get_node_or_null(btn_name)
		if node:
			node.visible = false

func _show_gameplay_buttons() -> void:
	for btn_name in ["SubmitButton", "CancelButton", "HintButton", "RestartButton"]:
		var node := $UI.get_node_or_null(btn_name)
		if node:
			node.visible = true

func _add_submit_button() -> void:
	var button := TextureButton.new()
	button.name           = "SubmitButton"
	button.texture_normal = load("res://Assets/checkmark.png")
	button.texture_hover  = button.texture_normal
	button.texture_pressed = button.texture_normal
	button.stretch_mode   = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var img := button.texture_normal.get_image()
	var mask := BitMap.new()
	mask.create_from_image_alpha(img)
	button.texture_click_mask = mask
	var screen := get_viewport_rect().size
	button.size           = Vector2(640, 100)
	button.position       = Vector2((screen.x - button.size.x) / 2.0, screen.y - button.size.y - 150)
	button.pivot_offset   = button.size / 2
	button.pressed.connect(_on_submit_pressed)
	$UI.add_child(button)

func _add_cancel_button() -> void:
	var button := TextureButton.new()
	button.name            = "CancelButton"
	button.texture_normal  = load("res://Assets/cancelbutton.png")
	button.texture_hover   = button.texture_normal
	button.texture_pressed = button.texture_normal
	button.stretch_mode    = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var img := button.texture_normal.get_image()
	var mask := BitMap.new()
	mask.create_from_image_alpha(img)
	button.texture_click_mask = mask
	var screen  := get_viewport_rect().size
	var margin  := 32
	button.size = Vector2(128, 128)
	button.position    = Vector2(screen.x - button.size.x - margin, screen.y - button.size.y - margin - 70)
	button.pivot_offset = button.size / 2
	button.pressed.connect(_on_cancel_pressed)
	$UI.add_child(button)

func _add_hint_button() -> void:
	var button := TextureButton.new()
	button.name            = "HintButton"
	button.texture_normal  = load("res://Assets/hintbutton.png")
	button.texture_hover   = button.texture_normal
	button.texture_pressed = button.texture_normal
	button.stretch_mode    = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var img := button.texture_normal.get_image()
	var mask := BitMap.new()
	mask.create_from_image_alpha(img)
	button.texture_click_mask = mask
	var screen := get_viewport_rect().size
	button.size = Vector2(128, 128)
	var margin := 32
	button.position    = Vector2(margin, screen.y - button.size.y - margin - 70)
	button.pivot_offset = button.size / 2
	button.pressed.connect(_on_hint_pressed)
	$UI.add_child(button)

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
	style.content_margin_left        = 24
	style.content_margin_right       = 24
	style.content_margin_top         = 12
	style.content_margin_bottom      = 12
	btn.add_theme_stylebox_override("normal", style)
	var sh := style.duplicate() as StyleBoxFlat
	sh.bg_color = base_col.lightened(0.12)
	btn.add_theme_stylebox_override("hover", sh)
	var sp := style.duplicate() as StyleBoxFlat
	sp.bg_color = base_col.darkened(0.12)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_font_override("font", load("res://Assets/Exo2-Bold.ttf"))
	btn.add_theme_font_size_override("font_size", 40)
	btn.add_theme_color_override("font_color",         Color(1, 1, 1))
	btn.add_theme_color_override("font_hover_color",   Color(1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.92, 1))

func _add_restart_button() -> void:
	var button := Button.new()
	button.name       = "RestartButton"
	button.text       = "Restart Level"
	button.focus_mode = Control.FOCUS_NONE
	_style_button(button, false)
	button.pressed.connect(_on_restart_pressed)
	$UI.add_child(button)

	# Wait for layout so size is known, then centre
	await get_tree().process_frame
	var screen := get_viewport_rect().size
	button.position = Vector2((screen.x - button.size.x) / 2.0, screen.y - 110)

func _add_home_button() -> void:
	var button := Button.new()
	button.name = "HomeButton"
	button.text = "⌂"
	button.flat = true
	button.custom_minimum_size = Vector2(88, 88)
	button.size                = Vector2(88, 88)
	button.pivot_offset        = Vector2(44, 44)

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
	button.add_theme_font_size_override("font_size", 48)
	button.add_theme_color_override("font_color",       Color(0.85, 0.9, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0,  1.0, 1.0))

	var screen := get_viewport_rect().size
	button.position = Vector2(screen.x - button.size.x - 16, 16)
	button.z_index  = 10

	button.pressed.connect(func(): AudioManager.play("select"); LoadingScreen.go_to(INTRO_SCENE))
	$UI.add_child(button)

# ── Dictionary ────────────────────────────────────────────────────────────────

func load_dictionary() -> void:
	var file := FileAccess.open("res://Assets/words.txt", FileAccess.READ)
	while file.get_position() < file.get_length():
		var word := file.get_line().strip_edges().to_upper()
		dictionary[word] = true
