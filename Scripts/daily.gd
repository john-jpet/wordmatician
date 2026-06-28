extends Node2D

const SAVE_PATH   := "user://daily_save.json"
const INTRO_SCENE := "res://Scenes/intro.tscn"

var tile_scene := preload("res://Scenes/letter_tile.tscn")

@onready var grid_node         := $Grid
@onready var current_word_label := $UI/CurrentWordLabel
@onready var status_label      := $UI/StatusLabel

const GRID_SIZE := 5
const TILE_SIZE := 128
const TILE_GAP  := 12

var board: Array           = []
var selected_letters: Array = []
var dictionary: Dictionary = {}
var daily_letters: Array   = []  # 25 letters for today (reshuffled on restart)
var daily_words: Array     = []  # the words that generated today's letters (hint source)
var solution_words: Array  = []  # words submitted by the player during the successful run
var tiles_remaining: int   = 0
var input_blocked: bool    = false
var _countdown_label: Label = null

var rng := RandomNumberGenerator.new()

# ── Entry point ──────────────────────────────────────────────────────────────

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

func _ready():
	load_dictionary()
	_add_home_button()
	_add_submit_button()
	_add_cancel_button()
	_add_hint_button()
	_style_button($UI/RestartButton, false)
	await get_tree().process_frame
	var rb := $UI/RestartButton
	rb.position.x = (get_viewport_rect().size.x - rb.size.x) / 2.0
	if _already_completed_today():
		_load_completion_data()
		_show_come_back_tomorrow()
		return
	var seed_val := _date_seed()
	daily_letters = _generate_daily_letters(seed_val, daily_words)
	_center_grid()
	_spawn_grid(daily_letters.duplicate())
	_block_input_briefly()

func _add_submit_button() -> void:
	var button := TextureButton.new()
	button.name = "SubmitButton"
	button.texture_normal = load("res://Assets/checkmark.png")
	button.texture_hover  = button.texture_normal
	button.texture_pressed = button.texture_normal
	button.stretch_mode   = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	var img := button.texture_normal.get_image()
	var mask := BitMap.new()
	mask.create_from_image_alpha(img)
	button.texture_click_mask = mask
	var screen := get_viewport_rect().size
	button.size     = Vector2(640, 100)
	button.position = Vector2((screen.x - button.size.x) / 2, screen.y - button.size.y - 150)
	button.pivot_offset = button.size / 2
	button.pressed.connect(_on_submit_pressed)
	$UI.add_child(button)

func _add_cancel_button() -> void:
	var button := TextureButton.new()
	button.name = "CancelButton"
	button.texture_normal  = load("res://Assets/cancelbutton.png")
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
	button.position = Vector2(screen.x - button.size.x - margin, screen.y - button.size.y - margin - 70)
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

# ── Hint logic ────────────────────────────────────────────────────────────────

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
	var candidates := daily_words.duplicate()
	candidates.shuffle()
	for word in candidates:
		var w := String(word).to_upper()
		var need := {}
		for i in w.length():
			var ch := w[i]
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
		# All original words are gone — any remaining tiles are bonus letters
		$UI/StatusLabel.text = "No hints left!"
		return

	# Greedily match letters to tiles
	var need := {}
	for i in word.length():
		var ch := word[i]
		need[ch] = need.get(ch, 0) + 1

	var hint_tiles := []
	for row in board:
		for tile in row:
			if tile == null or not is_instance_valid(tile):
				continue
			var L: String = tile.letter.to_upper()
			if need.get(L, 0) > 0:
				hint_tiles.append(tile)
				need[L] -= 1

	# Pulse tiles gold three times then restore
	for tile in hint_tiles:
		var tw := create_tween()
		tw.tween_property(tile, "modulate", Color(1, 0.85, 0.2), 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(tile, "modulate", Color(1, 1, 1),       0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(tile, "modulate", Color(1, 0.85, 0.2), 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(tile, "modulate", Color(1, 1, 1),       0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(tile, "modulate", Color(1, 0.85, 0.2), 0.25).set_trans(Tween.TRANS_SINE)
		tw.tween_property(tile, "modulate", Color(1, 1, 1),       0.25).set_trans(Tween.TRANS_SINE)

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
	button.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

	var screen := get_viewport_rect().size
	button.position = Vector2(screen.x - button.size.x - 16, 16)
	button.z_index = 10

	button.pressed.connect(_on_home_pressed)
	$UI.add_child(button)

# ── Date helpers ─────────────────────────────────────────────────────────────

func _date_seed() -> int:
	var t := Time.get_date_dict_from_system()
	return int(t["year"]) * 10000 + int(t["month"]) * 100 + int(t["day"])

func _today_string() -> String:
	var t := Time.get_date_dict_from_system()
	return "%d-%02d-%02d" % [int(t["year"]), int(t["month"]), int(t["day"])]

# ── Save / load ───────────────────────────────────────────────────────────────

func _already_completed_today() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	if data == null:
		return false
	return data.get("completed_date", "") == _today_string()

func _save_completion():
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"completed_date":  _today_string(),
		"intended_words":  daily_words,
		"solution_words":  solution_words,
	}))
	f.close()

func _load_completion_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not data is Dictionary:
		return
	for w in data.get("intended_words", []):
		daily_words.append(String(w))
	for w in data.get("solution_words", []):
		solution_words.append(String(w))

# ── Word / letter generation ──────────────────────────────────────────────────

func _generate_daily_letters(seed_val: int, out_words: Array = []) -> Array:
	rng.seed = seed_val
	var keys := dictionary.keys()
	# Filter: only words 3–8 letters, no J/Q/X/Z for fairness
	var pool: Array = []
	for w in keys:
		var s := String(w).to_upper()
		if s.length() >= 3 and s.length() <= 8 and not s.contains("J") \
				and not s.contains("Q") and not s.contains("X") and not s.contains("Z"):
			pool.append(s)

	# Pick words until we hit exactly 25 letters
	var chosen: Array = []
	var total := 0
	var max_attempts := 5000
	var attempt := 0
	while total < 25 and attempt < max_attempts:
		attempt += 1
		var w: String = pool[rng.randi() % pool.size()]
		var wlen := w.length()
		if total + wlen > 25:
			continue  # would overshoot
		var remaining_after := 25 - (total + wlen)
		if remaining_after > 0 and remaining_after < 3:
			continue  # would leave a gap too small for any valid word
		chosen.append(w)
		total += wlen
		if total == 25:
			break

	out_words.clear()
	for w in chosen:
		out_words.append(w)

	# Flatten to letter array and shuffle
	var letters: Array = []
	for w in chosen:
		for i in w.length():
			letters.append(w[i])
	_shuffle_array(letters, rng)
	return letters

func _shuffle_array(arr: Array, r: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := r.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

# ── Grid ──────────────────────────────────────────────────────────────────────

func _center_grid():
	var screen := get_viewport().get_visible_rect().size
	var grid_px := Vector2(
		GRID_SIZE * TILE_SIZE + (GRID_SIZE - 1) * TILE_GAP,
		GRID_SIZE * TILE_SIZE + (GRID_SIZE - 1) * TILE_GAP
	)
	grid_node.position = Vector2(
		(screen.x - grid_px.x) / 2.0 + TILE_SIZE / 2.0,
		(screen.y - grid_px.y) / 2.0
	)

func _spawn_grid(letters: Array):
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

			var delay := (x * 0.06) + (y * 0.03)
			var tw := create_tween()
			tw.tween_interval(delay)
			tw.tween_property(tile, "modulate:a", 1.0, 0.05)
			tw.parallel().tween_property(tile, "position", target, 0.45)\
				.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		board.append(row)

func _block_input_briefly():
	input_blocked = true
	await get_tree().create_timer(0.75).timeout
	input_blocked = false

# ── Input / selection ─────────────────────────────────────────────────────────

func letter_tapped(tile):
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

func _update_word_label():
	var w := ""
	for t in selected_letters:
		w += t.letter
	current_word_label.text = w

func _on_submit_pressed():
	_check_word()

func _on_cancel_pressed():
	for t in selected_letters:
		if is_instance_valid(t):
			t.modulate = Color(1, 1, 1)
	selected_letters.clear()
	current_word_label.text = ""

# ── Word checking ─────────────────────────────────────────────────────────────

func _check_word():
	if selected_letters.size() < 3:
		return
	var word := ""
	for t in selected_letters:
		word += t.letter
	word = word.to_upper()

	if not dictionary.has(word):
		_invalid_feedback()
		return

	solution_words.append(word)
	AudioManager.play("word_found")

	# Valid — remove tiles permanently, no refill
	input_blocked = true
	for t in selected_letters:
		if is_instance_valid(t):
			board[t.grid_pos.y][t.grid_pos.x] = null
			tiles_remaining -= 1
			var tw := create_tween()
			tw.tween_property(t, "scale", Vector2(1.4, 1.4), 0.1)
			tw.tween_property(t, "modulate:a", 0.0, 0.2)
			tw.tween_callback(func(): if is_instance_valid(t): t.queue_free())

	selected_letters.clear()
	current_word_label.text = ""

	await get_tree().create_timer(0.25).timeout
	_drop_tiles()
	input_blocked = false

	if tiles_remaining <= 0:
		_on_puzzle_cleared()

func _invalid_feedback():
	AudioManager.play("mistake")
	for t in selected_letters:
		var tw := create_tween()
		var orig: Vector2 = t.position
		tw.tween_property(t, "modulate", Color(1, 0.3, 0.3), 0.05)
		tw.tween_property(t, "position", orig + Vector2(5, 0), 0.05)
		tw.tween_property(t, "position", orig - Vector2(5, 0), 0.05)
		tw.tween_property(t, "position", orig, 0.05)
		tw.tween_property(t, "modulate", Color(1, 1, 1), 0.05)
	for t in selected_letters:
		t.modulate = Color(1, 1, 1)
	selected_letters.clear()
	current_word_label.text = ""

# ── Win / restart / exit ──────────────────────────────────────────────────────

func _on_puzzle_cleared():
	_save_completion()
	AudioManager.play("fanfare")
	StatsManager.record_daily_clear()
	input_blocked = true
	$UI/WinPanel.visible = true
	$UI/RestartButton.visible = false
	$UI/SubmitButton.visible  = false
	$UI/CancelButton.visible  = false
	$UI/HintButton.visible    = false
	_add_info_button($UI/WinPanel/VBox)

func _on_restart_pressed():
	AudioManager.play("select")
	solution_words.clear()
	selected_letters.clear()
	current_word_label.text = ""
	var reshuffled := daily_letters.duplicate()
	_shuffle_array(reshuffled, rng)
	_spawn_grid(reshuffled)
	_block_input_briefly()

func _on_home_pressed():
	AudioManager.play("select")
	LoadingScreen.go_to(INTRO_SCENE)

func _show_come_back_tomorrow():
	$UI/ComeBackPanel.visible = true
	$UI/RestartButton.visible = false
	$UI/SubmitButton.visible  = false
	$UI/CancelButton.visible  = false
	$UI/HintButton.visible    = false

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls              := LabelSettings.new()
	ls.font              = load("res://Assets/Exo2-Bold.ttf")
	ls.font_size         = 44
	ls.font_color        = Color(0.7, 0.85, 1.0)
	ls.outline_size      = 4
	ls.outline_color     = Color(0, 0, 0, 0.5)
	_countdown_label.label_settings = ls
	_countdown_label.text = _format_countdown(_seconds_until_midnight())
	$UI/ComeBackPanel/VBox.add_child(_countdown_label)

	_add_info_button($UI/ComeBackPanel/VBox)

func _seconds_until_midnight() -> int:
	var t := Time.get_time_dict_from_system()
	var elapsed := int(t["hour"]) * 3600 + int(t["minute"]) * 60 + int(t["second"])
	return 86400 - elapsed

func _format_countdown(secs: int) -> String:
	var h := secs / 3600
	var m := (secs % 3600) / 60
	var s := secs % 60
	return "Next puzzle in %02d:%02d:%02d" % [h, m, s]

func _process(_delta: float) -> void:
	if _countdown_label != null and is_instance_valid(_countdown_label):
		_countdown_label.text = _format_countdown(_seconds_until_midnight())

# ── Puzzle info popup ────────────────────────────────────────────────────────

func _add_info_button(vbox: VBoxContainer) -> void:
	var btn := Button.new()
	btn.text = "How was this puzzle made?"
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE

	var base_col := Color(0.10, 0.16, 0.38, 0.80)
	var style := StyleBoxFlat.new()
	style.bg_color                   = base_col
	style.corner_radius_top_left     = 18
	style.corner_radius_top_right    = 18
	style.corner_radius_bottom_left  = 18
	style.corner_radius_bottom_right = 18
	style.shadow_size                = 6
	style.shadow_color               = Color(0, 0, 0, 0.35)
	style.content_margin_left        = 20
	style.content_margin_right       = 20
	style.content_margin_top         = 10
	style.content_margin_bottom      = 10
	btn.add_theme_stylebox_override("normal", style)
	var sh := style.duplicate() as StyleBoxFlat
	sh.bg_color = base_col.lightened(0.12)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	btn.add_theme_font_override("font", load("res://Assets/Exo2-Regular.ttf"))
	btn.add_theme_font_size_override("font_size", 32)
	btn.add_theme_color_override("font_color",       Color(0.75, 0.85, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0,  1.0,  1.0))

	btn.pressed.connect(_show_puzzle_info_popup)
	vbox.add_child(btn)

func _show_puzzle_info_popup() -> void:
	# Full-screen dim
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 30
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	$UI.add_child(overlay)

	# Card
	var screen := get_viewport_rect().size
	var card_w := 580.0
	var card_h := 480.0
	var card   := ColorRect.new()
	card.color    = Color(0.08, 0.12, 0.25, 0.97)
	card.position = Vector2((screen.x - card_w) / 2.0, (screen.y - card_h) / 2.0)
	card.size     = Vector2(card_w, card_h)
	overlay.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(36, 36)
	vbox.size     = Vector2(card_w - 72, card_h - 72)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_theme_constant_override("separation", 18)
	card.add_child(vbox)

	var bold_font   = load("res://Assets/Exo2-Bold.ttf")
	var regular_font = load("res://Assets/Exo2-Regular.ttf")

	# Helper: add a header + word list pair
	var _add_section := func(header: String, words: Array) -> void:
		var h := Label.new()
		h.text = header
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var hs := LabelSettings.new()
		hs.font = bold_font
		hs.font_size = 34
		hs.font_color = Color(0.7, 0.82, 1.0)
		hs.outline_size = 3
		hs.outline_color = Color(0.05, 0.1, 0.25, 0.7)
		h.label_settings = hs
		vbox.add_child(h)

		var joined := ""
		for i in words.size():
			joined += String(words[i]).to_upper()
			if i < words.size() - 1:
				joined += "  ·  "

		var w := Label.new()
		w.text = joined
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var ws := LabelSettings.new()
		ws.font = regular_font
		ws.font_size = 34
		ws.font_color = Color(0.9, 0.94, 1.0)
		ws.outline_size = 3
		ws.outline_color = Color(0.05, 0.1, 0.25, 0.6)
		w.label_settings = ws
		vbox.add_child(w)

	_add_section.call("Created with:", daily_words)

	var divider := ColorRect.new()
	divider.color = Color(0.3, 0.45, 0.7, 0.4)
	divider.custom_minimum_size = Vector2(card_w - 72, 2)
	vbox.add_child(divider)

	var solution_label := "You solved it with:" if solution_words.size() > 0 \
		else "No solution recorded."
	_add_section.call(solution_label, solution_words)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "CLOSE"
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.15, 0.22, 0.42, 0.9)
	cs.corner_radius_top_left     = 16
	cs.corner_radius_top_right    = 16
	cs.corner_radius_bottom_left  = 16
	cs.corner_radius_bottom_right = 16
	cs.shadow_size = 6
	cs.shadow_color = Color(0, 0, 0, 0.35)
	cs.content_margin_left = 24
	cs.content_margin_right = 24
	cs.content_margin_top = 12
	cs.content_margin_bottom = 12
	close_btn.add_theme_stylebox_override("normal", cs)
	var csh := cs.duplicate() as StyleBoxFlat
	csh.bg_color = cs.bg_color.lightened(0.1)
	close_btn.add_theme_stylebox_override("hover", csh)
	close_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	close_btn.add_theme_font_override("font", bold_font)
	close_btn.add_theme_font_size_override("font_size", 34)
	close_btn.add_theme_color_override("font_color",       Color(0.85, 0.9, 1.0))
	close_btn.add_theme_color_override("font_hover_color", Color(1.0,  1.0, 1.0))
	close_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(close_btn)

	# Fade in
	card.modulate.a = 0.0
	overlay.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(overlay, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(card,    "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_SINE)

# ── Drop tiles ───────────────────────────────────────────────────────────────

func _drop_tiles():
	for x in range(GRID_SIZE):
		var empty_y := GRID_SIZE - 1
		for y in range(GRID_SIZE - 1, -1, -1):
			if board[y][x] != null:
				if y != empty_y:
					var tile = board[y][x]
					board[empty_y][x] = tile
					board[y][x] = null
					tile.grid_pos = Vector2i(x, empty_y)

					var target_pos := Vector2(
						x * (TILE_SIZE + TILE_GAP),
						empty_y * (TILE_SIZE + TILE_GAP)
					)
					var tw := create_tween()
					tw.tween_property(tile, "position", target_pos, 0.2)\
						.set_trans(Tween.TRANS_LINEAR)
					var squash := create_tween()
					squash.tween_interval(0.2)
					squash.tween_property(tile, "scale", Vector2(1.1, 0.9), 0.05)
					squash.tween_property(tile, "scale", Vector2(1.0, 1.0), 0.05)
				empty_y -= 1

# ── Dictionary ────────────────────────────────────────────────────────────────

func load_dictionary():
	var file := FileAccess.open("res://Assets/words.txt", FileAccess.READ)
	while file.get_position() < file.get_length():
		var word := file.get_line().strip_edges().to_upper()
		dictionary[word] = true
