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
var tiles_remaining: int   = 0
var input_blocked: bool    = false

var rng := RandomNumberGenerator.new()

# ── Entry point ──────────────────────────────────────────────────────────────

func _ready():
	load_dictionary()
	if _already_completed_today():
		_show_come_back_tomorrow()
		return
	var seed_val := _date_seed()
	daily_letters = _generate_daily_letters(seed_val)
	_center_grid()
	_spawn_grid(daily_letters.duplicate())
	_block_input_briefly()

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
	f.store_string(JSON.stringify({"completed_date": _today_string()}))
	f.close()

# ── Word / letter generation ──────────────────────────────────────────────────

func _generate_daily_letters(seed_val: int) -> Array:
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
		if total + w.length() <= 25:
			chosen.append(w)
			total += w.length()
		if total == 25:
			break
	# Fallback: pad with single common letters if needed
	var padding := ["E","A","R","I","O","T","N","S"]
	var pi := 0
	while total < 25:
		chosen.append(padding[pi % padding.size()])
		total += 1
		pi += 1

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

	# Valid — remove tiles permanently, no refill
	for t in selected_letters:
		if is_instance_valid(t):
			board[t.grid_pos.y][t.grid_pos.x] = null
			var tw := create_tween()
			tw.tween_property(t, "scale", Vector2(1.4, 1.4), 0.1)
			tw.tween_property(t, "modulate:a", 0.0, 0.2)
			tw.tween_callback(func(): if is_instance_valid(t): t.queue_free())
		tiles_remaining -= 1

	selected_letters.clear()
	current_word_label.text = ""

	if tiles_remaining <= 0:
		_on_puzzle_cleared()

func _invalid_feedback():
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
	input_blocked = true
	$UI/WinPanel.visible = true

func _on_restart_pressed():
	# Reshuffle the same letters for today
	selected_letters.clear()
	current_word_label.text = ""
	var reshuffled := daily_letters.duplicate()
	_shuffle_array(reshuffled, rng)
	_spawn_grid(reshuffled)
	_block_input_briefly()

func _on_exit_pressed():
	get_tree().change_scene_to_file(INTRO_SCENE)

func _show_come_back_tomorrow():
	$UI/ComeBackPanel.visible = true

func _on_back_pressed():
	get_tree().change_scene_to_file(INTRO_SCENE)

# ── Dictionary ────────────────────────────────────────────────────────────────

func load_dictionary():
	var file := FileAccess.open("res://Assets/words.txt", FileAccess.READ)
	while file.get_position() < file.get_length():
		var word := file.get_line().strip_edges().to_upper()
		dictionary[word] = true
