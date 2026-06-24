extends Node2D

#Preload Scenes
var popup_scene := preload("res://Scenes/pop_up_text.tscn")
var tile_scene := preload("res://Scenes/letter_tile.tscn")

@onready var grid_node := $Grid
@onready var popup_layer := $UI/PopupLayer

var active_popups: Array = []
var global_time := 0.0
var board: Array = []


const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const GRID_SIZE := 5
const TILE_SIZE := 128          # size of each tile (px)
const TILE_GAP  := 12          # gap between tiles (px)
# If you have a top UI bar and want the grid centered in the remaining space, set this.
# Otherwise leave 0 to center in the whole screen.
const UI_TOP_RESERVED := 0


var selected_letters = []
var dictionary = {}
var score: int = 0
var combo: int = 0
var base_points: int = 1  # starting value for scoring
var words_found: int = 0
var longest_word: String = ""

var displayed_score: int = 0
var score_tween: Tween = null


# --- Weighted letter setup ---
# Base weights ~ English frequency (percent-ish). You can tune freely.
var LETTER_WEIGHTS := [
	["E", 12.7], ["T", 9.1], ["A", 8.2], ["O", 7.5], ["I", 7.0],
	["N", 6.7], ["S", 6.3], ["H", 6.1], ["R", 6.0], ["D", 4.3],
	["L", 4.0], ["C", 2.8], ["U", 2.8], ["M", 2.4], ["W", 2.4],
	["F", 2.2], ["G", 2.0], ["Y", 2.0], ["P", 1.9], ["B", 1.5],
	["V", 1.0], ["K", 0.8], ["J", 0.15], ["X", 0.15], ["Q", 0.10], ["Z", 0.07]
]
var LETTER_FREQUENCY := {
	"E": 0, "T": 0, "A": 0, "O": 0, "I": 0,
	"N" : 0, "S": 0, "H": 0, "R": 0, "D": 0,
	"L": 0, "C": 0, "U": 0, "M": 0, "W": 0,
	"F": 0, "G": 0, "Y": 0, "P": 0, "B": 0,
	"V": 0, "K": 0, "J": 0, "X": 0, "Q": 0, "Z": 0
}
const LETTER_CAP = 5

const VOWEL_MULTIPLIER := 1.25  # boost vowels a bit more for QoL
var _cdf: PackedFloat32Array = []
var _letters: PackedStringArray = []
var _total_weight := 0.0

var time_left: float = 60.0  # start with 60 seconds
var elapsed_time: float = 0.0
var timer_running: bool = true

# --- Bomb tuning knobs ---
const BOMB_EXPLOSION_SHAPE := "3x3"   # "cross" or "3x3"
const BOMB_LOCALIZE_MULTS  := true      # true = each bomb uses only multipliers in its own radius
const BOMB_LOCAL_MULT_CAP  := 27.0      # cap a bomb's local mult (0 or <0 to disable)
const BOMB_PER_TILE_BASE   := 2         # base points per tile destroyed by bombs (before local mult)
const BOMB_MAX_ON_BOARD    := 2         # cap bombs visible at once
const BOMB_ALLOW_CHAIN_REACTIONS := true  # if false: bombs caught in blasts are removed but don't explode
const USE_LEGACY_BOMB_SCORING := true   # true = your original big scoring logic



@onready var score_label = $UI/ScoreLabel



# --- Power-up spawn rates ---
const PU_RATE_X2 := 0.1
const PU_RATE_X3 := 0.05
const PU_RATE_BOMB := 0.02
const PU_RATE_WILD := 0.03

# --- WILD CARD ---
var wild_card_exists := false

func _ready():
	var settings = LabelSettings.new()
	settings.font = preload("res://Assets/Exo2-Bold.ttf")
	settings.shadow_size = 20
	settings.shadow_color = Color(0, 0, 0, 0.4)
	settings.font_size = 100
	
	score_label.label_settings = settings
	
	randomize()
	_build_weight_cdf()
	_center_grid()
	generate_grid()
	ensure_playable_after_spawn()
	load_dictionary()
	_build_word_counts()
	create_buttons()
	$UI/CurrentWordLabel.text = ""

	# Block input during the intro animation
	# Longest tile delay: col 4 * 0.06 + row 4 * 0.03 + 0.45s animation = 0.69s
	timer_running = false
	set_process_input(false)
	await get_tree().create_timer(0.75).timeout
	set_process_input(true)
	timer_running = true

# Take a fast snapshot of board multiplicities + wildcards + bitmask
func _board_counts_mask_wild() -> Dictionary:
	var have := PackedInt32Array(); have.resize(26)
	var wild := 0
	var mask := 0
	for row in board:
		for t in row:
			if t == null or not is_instance_valid(t): continue
			if t.powerup == "wild_card":
				wild += 1
				continue
			var L := String(t.letter).to_upper()
			if L.length() != 1: continue
			var idx := LETTERS.find(L)
			if idx >= 0:
				have[idx] += 1
				mask |= (1 << idx)
	return {"have": have, "wild": wild, "mask": mask}

func board_has_playable_word():
	var snap := _board_counts_mask_wild()
	var have: PackedInt32Array = snap["have"] as PackedInt32Array
	var wild: int = int(snap["wild"])

	for item in _dict_precomp:
		var need: PackedInt32Array = item["need"] as PackedInt32Array
		var word_str: String = String(item["word"])  # your stored word
		var deficit := 0

		for i in 26:
			var d := need[i] - have[i]
			if d > 0:
				deficit += d
				if deficit > wild:
					break

		if deficit <= wild:
			
			print("[Playable word found]: ", word_str)
			return true  # early exit when we find one

	
	print("[No playable words found on this board]")
	return false


var _dict_precomp: Array = []  # entries: {word:String, len:int, need:PackedInt32Array}
var _dict_by_length: Dictionary = {}  # int -> Array[String], for fast wildcard lookup

func _build_word_counts():
	_dict_precomp.clear()
	_dict_by_length.clear()
	for w in dictionary.keys():
		var u := String(w).to_upper()
		if u.length() < 3:
			continue
		var need := PackedInt32Array()
		need.resize(26)
		for i in u.length():
			var ch := u[i]
			var idx := LETTERS.find(ch)
			if idx >= 0:
				need[idx] += 1
		_dict_precomp.append({"word": u, "len": u.length(), "need": need})
		# Group by length for O(1) wildcard candidate lookup
		if not _dict_by_length.has(u.length()):
			_dict_by_length[u.length()] = []
		_dict_by_length[u.length()].append(u)
	_dict_precomp.sort_custom(func(a, b): return a.len < b.len)
	
func _current_letter_counts() -> Dictionary:
	var d := {}
	for row in board:
		for t in row:
			if t == null or not is_instance_valid(t):
				continue
			# Don't count wildcards toward any letter cap
			if t.powerup == "wild_card":
				continue
			var L := String(t.letter).to_upper()
			if L.length() != 1:
				continue
			d[L] = int(d.get(L, 0)) + 1
	return d

func ensure_playable_after_spawn(max_attempts := 3, reroll_each := 5) -> void:
	var attempt := 0
	while attempt < max_attempts and not board_has_playable_word():
		_reroll_some_tiles(reroll_each)
		attempt += 1
	# Final guarantee
	if not board_has_playable_word():
		_force_embed_easy_word_scatter()
# Prefer common letters; skip wildcards
const _COMMON := ["E","A","R","I","O","T","N","S","L","C","U","D","M"]

func _reroll_some_tiles(k := 5) -> void:
	# Gather candidate cells
	var cells: Array = []
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var t = board[y][x]
			if t != null and is_instance_valid(t) and t.powerup != "wild_card":
				cells.append(Vector2i(x, y))
	cells.shuffle()

	# Start from current counts so the cap is honored across the batch
	var live_counts := _current_letter_counts()  # your Dictionary<String,int>

	for i in range(min(k, cells.size())):
		var pos: Vector2i = cells[i]
		var t = board[pos.y][pos.x]
		if t == null or not is_instance_valid(t): continue

		# Bias a bit toward common letters by temporarily nudging weights
		var newL := _pick_weighted_letter(live_counts)  # already cap-aware
		# If you want extra bias: try reroll until common (limit tries)
		var tries := 0
		while not (_COMMON.has(newL)) and tries < 2:
			newL = _pick_weighted_letter(live_counts)
			tries += 1

		# Update the tile’s letter but keep its powerup
		if t.has_method("set_letter"):
			t.set_letter(newL, t.powerup)
		else:
			t.letter = newL
func _force_embed_easy_word_scatter():
	# Collect easy 3–4 letter candidates without J/Q/X/Z
	var candidates: Array[String] = []
	for entry in _dict_precomp:
		var w: String = String(entry["word"])
		var wlen: int = int(entry["len"])
		if wlen >= 3 and wlen <= 4 and not w.match(".*[JQXZ].*"):
			candidates.append(w)

	if candidates.is_empty():
		return

	var chosen: String = candidates[randi() % candidates.size()]

	# Pick random distinct tiles and overwrite letters (scatter; no adjacency needed)
	var spots: Array = []
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var t = board[y][x]
			if t != null and is_instance_valid(t):
				spots.append(Vector2i(x, y))
	spots.shuffle()

	var limit: int = int(min(chosen.length(), spots.size()))
	for i in range(limit):
		var pos: Vector2i = spots[i]
		var t = board[pos.y][pos.x]
		if t == null or not is_instance_valid(t): continue
		var L := String(chosen[i])
		if t.has_method("set_letter"):
			t.set_letter(L, t.powerup)
		else:
			t.letter = L

func _roll_powerup() -> String:
	# --- Handle Wild Card separately ---
	if not wild_card_exists and randf() < PU_RATE_WILD:
		wild_card_exists = true
		return "wild_card"

	# --- Now roll the rest independently ---
	var r := randf()
	if r < PU_RATE_BOMB:
		return "bomb"
	elif r < PU_RATE_BOMB + PU_RATE_X3:
		return "x3"
	elif r < PU_RATE_BOMB + PU_RATE_X3 + PU_RATE_X2:
		return "x2"
	return "none"

func create_submit_button() -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = load("res://Assets/checkmark.png")
	button.texture_hover = button.texture_normal
	button.texture_pressed = button.texture_normal
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED

	# Convert the texture's alpha into a BitMap for accurate clicking
	var img := button.texture_normal.get_image()
	var click_mask := BitMap.new()
	click_mask.create_from_image_alpha(img)
	button.texture_click_mask = click_mask
	var screen_size = get_viewport_rect().size

	# Example: center horizontally, place near bottom
	button.size = Vector2(640, 100)  # adjust manually as needed
	button.position = Vector2(
		(screen_size.x - button.size.x) / 2,  # center horizontally
		screen_size.y - button.size.y - 150    # offset from bottom
	)
	
	


	button.pressed.connect(_on_submit_pressed)
	return button

func create_cancel_button() -> TextureButton:
	var button := TextureButton.new()
	button.name = "CancelButton"
	
	# Textures
	button.texture_normal = load("res://Assets/cancelbutton.png")   # <-- your red X png
	button.texture_hover  = button.texture_normal
	button.texture_pressed = button.texture_normal

	# Keep aspect; we’ll size/position manually
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED

	# Precise click area from PNG alpha
	var img := button.texture_normal.get_image()
	var mask := BitMap.new()
	mask.create_from_image_alpha(img)
	button.texture_click_mask = mask

	# Size & position (square, bottom-right, with margin)
	var screen := get_viewport_rect().size
	button.size = Vector2(128, 128)               # adjust if needed
	var margin := 32
	button.position = Vector2(
		screen.x - button.size.x - margin,
		screen.y - button.size.y - margin - 70
	)

	# Centered scaling pivot (nice for click/hover anims)
	button.pivot_offset = button.size / 2

	# Signal
	button.pressed.connect(_on_cancel_pressed)

	return button

func create_home_button() -> Button:
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

	# Top-left, below status bar area
	var screen := get_viewport_rect().size
	button.position = Vector2(screen.x - button.size.x - 16, 16)

	button.pressed.connect(_on_home_pressed)
	return button

func create_buttons():
	# === Submit Button ===
	var submit_button = create_submit_button()
	submit_button.name = "SubmitButton"
	submit_button.pivot_offset = submit_button.size / 2
	$UI.add_child(submit_button)

	# === Cancel Button ===
	var cancel_button := create_cancel_button()
	cancel_button.name = "CancelButton"
	$UI.add_child(cancel_button)

	# === Home Button ===
	var home_button := create_home_button()
	home_button.name = "HomeButton"
	$UI.add_child(home_button)


const INTRO_SCENE := "res://Scenes/intro.tscn"

func _on_home_pressed():
	LoadingScreen.go_to(INTRO_SCENE)

func _on_submit_pressed():
	var tween = get_tree().create_tween()
	tween.tween_property($UI/SubmitButton, "scale", Vector2(0.95, 0.95), 0.05)
	tween.tween_property($UI/SubmitButton, "modulate", Color(1.2, 1.2, 1.2, 1), 0.05)
	tween.tween_interval(0.05)
	tween.tween_property($UI/SubmitButton, "scale", Vector2(1, 1), 0.1)
	tween.tween_property($UI/SubmitButton, "modulate", Color(1, 1, 1, 1), 0.1)
	check_word()


func _on_cancel_pressed():
	var tween = get_tree().create_tween()
	tween.tween_property($UI/CancelButton, "scale", Vector2(0.95, 0.95), 0.05)
	tween.tween_property($UI/CancelButton, "modulate", Color(1.2, 1.2, 1.2, 1), 0.05)
	tween.tween_interval(0.05)
	tween.tween_property($UI/CancelButton, "scale", Vector2(1, 1), 0.1)
	tween.tween_property($UI/CancelButton, "modulate", Color(1, 1, 1, 1), 0.1)
	for tile in selected_letters:
		if is_instance_valid(tile):
			tile.modulate = Color(1, 1, 1)
	selected_letters.clear()
	$UI/CurrentWordLabel.text = ""

func update_score_display():
	if score_tween and score_tween.is_running():
		score_tween.kill()
	score_tween = create_tween()
	
	score_tween.tween_property(self, "displayed_score", score, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func animate_score_change():
	
	var tween = create_tween()
	tween.tween_property($UI/ScoreLabel, "scale", Vector2(1.1, 1.1), 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property($UI/ScoreLabel, "scale", Vector2(1, 1), 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_property($UI/ScoreLabel, "modulate", Color(1, 1, 0.8), 0.05) # brief flash
	tween.tween_property($UI/ScoreLabel, "modulate", Color(1, 1, 1), 0.1)
	
func animate_timer_warning():

	var label = $UI/TimerLabel

	# Only run if it's not already animating
	if label.has_meta("warning_active") and label.get_meta("warning_active"):
		return

	label.set_meta("warning_active", true)

	var tween = create_tween()
	tween.set_loops()  # Loop indefinitely until we stop it
	
	tween.tween_property(label, "scale", Vector2(1.1, 1.1), 0.25)
	tween.tween_property(label, "modulate", Color(1, 0.4, 0.4), 0.25) # fade red
	tween.tween_property(label, "scale", Vector2(1, 1), 0.25)
	tween.tween_property(label, "modulate", Color(1, 1, 1), 0.25)     # back to white
	
	label.set_meta("warning_tween", tween)

func stop_timer_warning():
	var label = $UI/TimerLabel
	if label.has_meta("warning_tween"):
		var tween = label.get_meta("warning_tween")
		if tween and tween.is_running():
			tween.kill()
	label.modulate = Color(1, 1, 1)
	label.scale = Vector2(1, 1)
	label.set_meta("warning_active", false)


func show_bonus_popup(kind: String, value: int):
	var popup = popup_scene.instantiate()
	popup_layer.add_child(popup)

	# --- Keep track of active popups ---
	active_popups.append(popup)

	# Position near top-center
	var screen = get_viewport().get_visible_rect().size
	var base_y := 400
	var vertical_spacing := 100

	# Offset based on how many popups already exist
	var offset := vertical_spacing * (active_popups.size() - 1)
	popup.position = Vector2(screen.x / 2, base_y + offset)


	match kind:
		"length":
			popup.show_text("Length Bonus! x%d" % value, Color.CYAN)
		"combo":
			popup.show_text("Combo! x%d" % value, Color.YELLOW)
		"multiplier":
			popup.show_text("Multiplier! x%d" % value, Color.DARK_ORANGE)
		_:
			popup.show_text(kind, Color.WHITE)

	# --- Remove from list after it's gone ---
	popup.get_tree().create_timer(0.8).timeout.connect(func():
		if popup in active_popups:
			active_popups.erase(popup)
	)



func _process(delta):
	global_time += delta
	if timer_running:
		elapsed_time += delta
		time_left -= delta
		if time_left <= 0:
			time_left = 0
			timer_running = false
			stop_timer_warning()
			game_over()
		
		# Timer warning trigger
		if time_left <= 10.0:
			animate_timer_warning()
		else:
			stop_timer_warning()

		$UI/TimerLabel.text = " %d" % ceil(time_left)
		$UI/ScoreLabel.text = str(displayed_score)


func _notification(what):
	# Recenter if window size changes during testing
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_center_grid()

# ---------- Layout helpers ----------
func _grid_pixel_size() -> Vector2:
	var w = GRID_SIZE * TILE_SIZE + (GRID_SIZE - 1) * TILE_GAP
	var h = GRID_SIZE * TILE_SIZE + (GRID_SIZE - 1) * TILE_GAP
	return Vector2(w, h)

func _center_grid():
	var screen := get_viewport().get_visible_rect().size
	var grid_px := _grid_pixel_size()

	# If you keep a top UI area, center within the remaining space:
	var top = UI_TOP_RESERVED
	var remaining_h = max(1.0, screen.y - top)
	var origin_x = (screen.x - grid_px.x) / 2.0 + (TILE_SIZE / 2.0)
	var origin_y = top + (remaining_h - grid_px.y) / 2.0
	grid_node.position = Vector2(origin_x, origin_y)

# ---------- Grid creation ----------
func generate_grid():
	# Clear previous tiles (if regenerating)
	for child in grid_node.get_children():
		child.queue_free()
	board.clear()

	for y in range(GRID_SIZE):
		var row: Array = []
		for x in range(GRID_SIZE):
			LETTER_FREQUENCY = _current_letter_counts()
			var letter := _pick_weighted_letter(LETTER_FREQUENCY)
			var tile = tile_scene.instantiate()
			tile.set_letter(letter, "none")

			tile.grid_pos = Vector2i(x, y)

			var target_pos = Vector2(
				x * (TILE_SIZE + TILE_GAP),
				y * (TILE_SIZE + TILE_GAP)
			)

			# Start tiles above the screen
			tile.position = Vector2(target_pos.x, -TILE_SIZE * (GRID_SIZE + 1))
			tile.modulate.a = 0.0
			grid_node.add_child(tile)
			row.append(tile)

			# Stagger delay: column-first so tiles fall in waves left to right
			var delay := (x * 0.06) + (y * 0.03)

			var tween := create_tween()
			tween.tween_interval(delay)
			tween.tween_property(tile, "modulate:a", 1.0, 0.05)
			tween.parallel().tween_property(tile, "position", target_pos, 0.45)\
				.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

		board.append(row)

# ---------- Weighted letter picker ----------
func _build_weight_cdf():
	_cdf.clear()
	_letters.clear()
	_total_weight = 0.0

	for pair in LETTER_WEIGHTS:
		var ch: String = pair[0]
		var w: float = pair[1]

		# Boost vowels a bit (A, E, I, O, U)
		if ch == "A" or ch == "E" or ch == "I" or ch == "O" or ch == "U":
			w *= VOWEL_MULTIPLIER

		_total_weight += w
		_cdf.append(_total_weight)
		_letters.append(ch)

func _pick_weighted_letter(live_counts: Dictionary) -> String:
	var total := 0.0
	var bag := []  # [letter, weight_after_cap]

	for pair in LETTER_WEIGHTS:
		var L: String = pair[0]
		var w: float = pair[1]
		if int(live_counts.get(L, 0)) >= LETTER_CAP:
			w = 0.0
		bag.append([L, w])
		total += w

	# Pathological fallback (should be impossible on 5x5, but safe):
	if total <= 0.0:
		bag.clear()
		total = 0.0
		for pair in LETTER_WEIGHTS:
			bag.append([pair[0], float(pair[1])])
			total += float(pair[1])

	var r := randf() * total
	for p in bag:
		r -= p[1]
		if r <= 0.0:
			var L: String = String(p[0])  # <-- cast
			live_counts[L] = int(live_counts.get(L, 0)) + 1
			return L

	# Last-ditch fallback
	var L2: String = String(bag.back()[0])  # <-- cast
	live_counts[L2] = int(live_counts.get(L2, 0)) + 1
	return L2



func letter_tapped(tile):
	if tile in selected_letters:
		# --- Deselect ---
		selected_letters.erase(tile)
		update_current_word_display()
		tile.modulate = Color(1, 1, 1)  # Revert to normal color
	else:
		# --- Select ---
		selected_letters.append(tile)
		update_current_word_display()
		tile.modulate = Color(0.7, 0.7, 1)  # Highlight

func load_dictionary():
	var file = FileAccess.open("res://Assets/words.txt", FileAccess.READ)
	while file.get_position() < file.get_length():
		var word = file.get_line().strip_edges().to_upper()
		dictionary[word] = true

# Simple wildcard match: '.' matches any letter. No regex overhead.
func _wild_matches(pattern: String, candidate: String) -> bool:
	if pattern.length() != candidate.length():
		return false
	for i in pattern.length():
		if pattern[i] != "." and pattern[i] != candidate[i]:
			return false
	return true
		
func _unhandled_input(event):
	if event.is_action_pressed("ui_accept"):
		check_word()



func check_word():
	var word := ""
	var word_mult := 0.0
	var has_bomb := false
	var has_wild := false
	var base_word_points := 0
	var bomb_bonus := 0

	# --- Build the word and detect powerups ---
	for tile in selected_letters:
		if tile.powerup == "wild_card":
			has_wild = true
			word += "."
		else:
			word += tile.letter

		if tile.powerup == "x2":
			word_mult += 2.0
		elif tile.powerup == "x3":
			word_mult += 3.0
		elif tile.powerup == "bomb":
			bomb_bonus += 1000
			has_bomb = true

	var valid := false
	var resolved_word := word  # actual dictionary word (wildcards replaced)
	if word.length() > 2:
		if has_wild:
			var candidates: Array = _dict_by_length.get(word.length(), [])
			for key in candidates:
				if _wild_matches(word, key):
					valid = true
					resolved_word = key
					break
		else:
			valid = dictionary.has(word)
			resolved_word = word

	if not valid:
		for tile in selected_letters:
			tile.modulate = Color(1, 1, 1)
		invalid_word_feedback(selected_letters)
		combo = 0
		selected_letters.clear()
		$UI/CurrentWordLabel.text = ""
		return

	# ---------------------
	# Score calculation (ONE award only)
	# ---------------------

	# Base word score (without combo)
	base_word_points += calculate_word_score(word)
	

	var points_to_add := 0
	var tiles_to_remove := []
	var popup_mult_to_show := 1

	if has_bomb:
		# Collect explosion tiles
		var explosion_dict := _compute_bomb_explosion_tiles(selected_letters)

		# Union selected + explosion for removal
		var all_to_clear := {}
		for k in explosion_dict.keys():
			all_to_clear[k] = explosion_dict[k]
		for t in selected_letters:
			if t != null and is_instance_valid(t):
				var key = str(t.grid_pos.x, "_", t.grid_pos.y)
				all_to_clear[key] = t

		
		
		var explosion_points := _sum_explosion_points(explosion_dict)
		print("EXPLOSION POINTS: ", explosion_points)
		word_mult = _overall_multiplier(selected_letters, explosion_dict)
		#print("BOMB MULTIPLIER: ", overall_mult)
		points_to_add = int(base_word_points + explosion_points)

		tiles_to_remove = all_to_clear.values()
	else:
		# No bomb: just the word score (already includes word_mult)
		points_to_add = base_word_points
		popup_mult_to_show = int(word_mult)

		tiles_to_remove = selected_letters.duplicate()

	# Apply combo ONCE
	var COMBO_BONUS := 0.0
	if combo < 10:
		COMBO_BONUS = (1 + combo * 0.1)
		points_to_add = int(points_to_add * COMBO_BONUS)
	else:
		COMBO_BONUS = 2
		points_to_add = int(points_to_add * COMBO_BONUS)
		
	if word_mult > 0:
		points_to_add = int(points_to_add * word_mult)
	
	points_to_add += bomb_bonus
	# Apply results ONCE
	print("COMBO BONUS: ", COMBO_BONUS)
	print("BOMB BONUS: ", bomb_bonus)
	print("MULTIPLIER: ", word_mult)
	print("WORD SCORE: ", points_to_add)
	popup_mult_to_show = int(word_mult)
	score += points_to_add
	combo += 1
	words_found += 1
	if resolved_word.length() > longest_word.length():
		longest_word = resolved_word
	time_left = min(60.0, time_left + word.length())
	update_score_display()
	animate_score_change()

	# Remove tiles (ONE removal path)
	if has_bomb:
		var all_to_clear_dict := {}
		for t in tiles_to_remove:
			if t != null and is_instance_valid(t):
				var key = str(t.grid_pos.x, "_", t.grid_pos.y)
				all_to_clear_dict[key] = t
		_remove_tiles_dict(all_to_clear_dict)
	else:
		remove_selected()
		
	# Reset selection + label
	selected_letters.clear()
	$UI/CurrentWordLabel.text = ""

	# Popups (show once)
	if word.length() > 4:
		show_bonus_popup("length", word.length())
	if combo > 1:
		show_bonus_popup("combo", combo)
	if popup_mult_to_show > 1:
		show_bonus_popup("multiplier", popup_mult_to_show)

	

# Collect all blast tiles from bombs in the selected word
func _compute_bomb_explosion_tiles(source_tiles: Array) -> Dictionary:
	var to_clear := {}    # "x_y" -> tile
	var frontier: Array = []

	# Start from bombs in the selection
	for t in source_tiles:
		if t != null and is_instance_valid(t) and t.powerup == "bomb":
			frontier.append(t)

	# BFS chain reaction over bombs
	while frontier.size() > 0:
		var b = frontier.pop_back()
		if b == null or not is_instance_valid(b):
			continue

		var bx = b.grid_pos.x
		var by = b.grid_pos.y
		to_clear[str(bx, "_", by)] = b

		var area := _get_bomb_area(bx, by)
		for pos in area:
			var x = pos.x
			var y = pos.y
			if x < 0 or x >= GRID_SIZE or y < 0 or y >= GRID_SIZE:
				continue

			var t = board[y][x]
			if t == null or not is_instance_valid(t):
				continue

			var k = str(x, "_", y)
			if not to_clear.has(k):
				to_clear[k] = t
				if t.powerup == "bomb":
					frontier.append(t)

	return to_clear


# Sum bomb points only from the explosion dictionary (no multipliers here)
func _sum_explosion_points(explosion_dict: Dictionary) -> int:
	var sum := 0
	for k in explosion_dict.keys():
		var t = explosion_dict[k]
		if t != null and is_instance_valid(t):
			sum += 5
	return sum


# Build one big multiplier from x2/x3 tiles in (selection ∪ explosion)
func _overall_multiplier(selected_tiles: Array, explosion_dict: Dictionary) -> float:
	var mult := 0.0
	var seen := {}
	print("--- Checking multipliers ---")

	# From selected tiles
	for t in selected_tiles:
		if t == null or not is_instance_valid(t):
			continue
		var key = str(t.grid_pos.x, "_", t.grid_pos.y)
		if seen.has(key):
			continue
		seen[key] = true
		if t.powerup == "x2":
			print("→ x2 in WORD at", t.grid_pos)
			mult += 2.0
		elif t.powerup == "x3":
			print("→ x3 in WORD at", t.grid_pos)
			mult += 3.0
	
	# From explosion tiles (don’t double-count)
	for k in explosion_dict.keys():
		if seen.has(k):
			continue
		var t = explosion_dict[k]
		if t == null or not is_instance_valid(t):
			continue
		if t.powerup == "x2":
			print("→ x2 in EXPLOSION at", t.grid_pos)
			mult += 2.0
		elif t.powerup == "x3":
			print("→ x3 in EXPLOSION at", t.grid_pos)
			mult += 3.0
	if mult == 0:
		mult = 1.0
	
	return mult

func _remove_tiles_dict(to_clear: Dictionary) -> void:
	# --- quick visual flash ---
	var flash = ColorRect.new()
	flash.color = Color(1, 0.8, 0.2, 0.35)  # warm orange glow
	flash.size = get_viewport_rect().size
	flash.z_index = 999
	add_child(flash)

	var flash_tween = create_tween()
	flash_tween.tween_property(flash, "modulate:a", 0.6, 0.1)
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.2)
	flash_tween.tween_callback(func():
		if is_instance_valid(flash):
			flash.queue_free())

	# --- apply per-tile removal animation ---
	for k in to_clear.keys():
		var t = to_clear[k]
		if t == null or not is_instance_valid(t):
			continue
		board[t.grid_pos.y][t.grid_pos.x] = null

		# little pop + fade instead of simple remove_tile()
		var tween = create_tween()
		tween.tween_property(t, "scale", Vector2(1.5, 1.5), 0.1)
		tween.tween_property(t, "modulate:a", 0, 0.2)
		tween.tween_callback(func():
			if is_instance_valid(t):
				t.queue_free())
		# --- WILD CARD RESET ---
		# Check if any wild card still exists after removals
	


	# small pause before gravity
	await get_tree().create_timer(0.25).timeout
	drop_tiles()
	refill_tiles()
	ensure_playable_after_spawn.call_deferred()


func _in_bounds(x:int, y:int) -> bool:
	return x >= 0 and x < GRID_SIZE and y >= 0 and y < GRID_SIZE

func _cross_area(cx:int, cy:int) -> Array:
	var A : Array = []
	var dirs = [[0,0],[1,0],[-1,0],[0,1],[0,-1]]
	for d in dirs:
		var x = cx + d[0]
		var y = cy + d[1]
		if _in_bounds(x,y):
			A.append(Vector2i(x,y))
	return A

func _get_bomb_area(x:int, y:int) -> Array:
	if BOMB_EXPLOSION_SHAPE == "cross":
		return _cross_area(x, y)

	# "3x3" (neighbors + center) without list comprehension
	var A: Array = []
	A.append(Vector2i(x, y))                 # include center
	for p in _neighbors_3x3(x, y):           # your helper already returns Vector2i
		A.append(p)
	return A

func _local_multiplier_for_positions(positions:Array) -> float:
	if not BOMB_LOCALIZE_MULTS:
		return 1.0
	var mult := 1.0
	for p in positions:
		var t = board[p.y][p.x]
		if t == null or not is_instance_valid(t):
			continue
		match t.powerup:
			"x2":
				mult *= 2.0
			"x3":
				mult *= 3.0
	# optional safety cap
	if BOMB_LOCAL_MULT_CAP > 0.0 and mult > BOMB_LOCAL_MULT_CAP:
		mult = BOMB_LOCAL_MULT_CAP
	return mult

func _resolve_bombs_after_word(selected_tiles:Array) -> Dictionary:
	# Queue bombs found in the selected word
	var queue : Array = []
	for t in selected_tiles:
		if t != null and is_instance_valid(t) and t.powerup == "bomb":
			queue.append(Vector2i(t.grid_pos.x, t.grid_pos.y))

	var removed := {}           # key "x_y" -> tile
	var exploded := {}          # set of positions (Vector2i) we've exploded already
	var total_points := 0

	while queue.size() > 0:
		var bpos : Vector2i = queue.pop_front()
		if exploded.has(bpos):
			continue
		exploded[bpos] = true

		# If bomb is gone (maybe already removed), skip
		if not _in_bounds(bpos.x, bpos.y):
			continue
		var bomb_node = board[bpos.y][bpos.x]
		if bomb_node == null or not is_instance_valid(bomb_node) or bomb_node.powerup != "bomb":
			continue

		var area := _get_bomb_area(bpos.x, bpos.y)
		var local_mult := _local_multiplier_for_positions(area)

		# Tally points for *newly* affected tiles, and mark for removal
		var newly_hit := 0
		for p in area:
			var key = str(p.x, "_", p.y)
			if not removed.has(key):
				var t = board[p.y][p.x]
				if t != null and is_instance_valid(t):
					removed[key] = t
					newly_hit += 1

		total_points += int(round(BOMB_PER_TILE_BASE * newly_hit * local_mult))

		# Optional chain reaction: enqueue bombs inside area
		if BOMB_ALLOW_CHAIN_REACTIONS:
			for p in area:
				var n = board[p.y][p.x]
				if n != null and is_instance_valid(n) and n.powerup == "bomb":
					var np = Vector2i(n.grid_pos.x, n.grid_pos.y)
					if not exploded.has(np):
						queue.append(np)
		# If chain reactions are disabled, bombs in area will be removed with everything else but won't explode.

	return {"points": total_points, "to_remove": removed}

func _neighbors_3x3(x: int, y: int) -> Array:
	var out: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nx := x + dx
			var ny := y + dy
			if nx >= 0 and nx < GRID_SIZE and ny >= 0 and ny < GRID_SIZE:
				out.append(Vector2i(nx, ny))
	return out


func _bomb_tile_points(tile) -> int:
	if tile == null or not is_instance_valid(tile):
		return 0

	# Base value per tile removed
	var base := 2

	# Rare letter bonus
	if tile.letter in ["Q", "Z", "X", "J"]:
		base += 3

	# Apply per-tile multiplier
	var mult := 1.0
	match tile.powerup:
		"x2":
			mult = 2.0
		"x3":
			mult = 3.0
		"bomb":
			# Give bombs themselves a small inherent value bump
			mult = 1.5

	return int(base * mult)



func _trigger_bomb_chain(source_tiles: Array) -> void:
	var frontier: Array = []
	var to_clear := {} # key = "x_y" → tile

	# --- 1. Seed frontier with any bombs in selected tiles ---
	for t in source_tiles:
		if t != null and is_instance_valid(t) and t.powerup == "bomb":
			frontier.append(t)
		else:
			# Non-bomb tiles in the same word also count as part of total removal
			var key = str(t.grid_pos.x, "_", t.grid_pos.y)
			to_clear[key] = t

	# --- 2. Expand the bomb chain ---
	while frontier.size() > 0:
		var b = frontier.pop_back()
		if b == null or not is_instance_valid(b):
			continue

		var bx = b.grid_pos.x
		var by = b.grid_pos.y
		var key_self = str(bx, "_", by)
		to_clear[key_self] = b

		for pos in _neighbors_3x3(bx, by):
			var x = pos.x
			var y = pos.y
			if x < 0 or x >= GRID_SIZE or y < 0 or y >= GRID_SIZE:
				continue

			var t = board[y][x]
			if t == null or not is_instance_valid(t):
				continue

			var key = str(x, "_", y)
			if not to_clear.has(key):
				to_clear[key] = t
				if t.powerup == "bomb":
					frontier.append(t)

	# --- 3. Add points for all destroyed tiles ---
	var gained := 0
	for k in to_clear.keys():
		var t = to_clear[k]
		if t == null or not is_instance_valid(t):
			continue
		gained += _bomb_tile_points(t)

	score += gained
	update_score_display()
	animate_score_change()



	# --- 4. Destroy all affected tiles with animation ---
	for k in to_clear.keys():
		var t = to_clear[k]
		if t == null or not is_instance_valid(t):
			continue
		board[t.grid_pos.y][t.grid_pos.x] = null
		var tween = create_tween()
		tween.tween_property(t, "scale", Vector2(1.5, 1.5), 0.1)
		tween.tween_property(t, "modulate:a", 0, 0.2)
		tween.tween_callback(func():
			if is_instance_valid(t):
				t.queue_free()
		)

	# --- 5. Deselect everything to prevent stale highlights ---
	for tile in selected_letters:
		if is_instance_valid(tile):
			tile.modulate = Color(1, 1, 1)
	selected_letters.clear()
	$UI/CurrentWordLabel.text = ""
	# --- 6. Collapse and refill the grid ---
	await get_tree().create_timer(0.25).timeout
	drop_tiles()
	refill_tiles()
	ensure_playable_after_spawn.call_deferred()


func remove_selected():
	print("Removing selected tiles:", selected_letters.size())
	for tile in selected_letters:
		print(" -", tile.letter, tile.grid_pos, tile.powerup)
		board[tile.grid_pos.y][tile.grid_pos.x] = null
		remove_tile(tile)
	selected_letters.clear()
	
	drop_tiles()
	refill_tiles()
	ensure_playable_after_spawn.call_deferred()


func remove_tile(tile):
	var offset = Vector2(randf_range(-20,20), randf_range(-20,20))
	var tween = create_tween()
	tween.tween_property(tile, "position", tile.position + offset, 0.2).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(tile, "modulate:a", 0, 0.2)
	tween.tween_callback(Callable(tile, "queue_free"))

	
func drop_tiles():
	for x in range(GRID_SIZE):
		var empty_y = GRID_SIZE - 1
		for y in range(GRID_SIZE - 1, -1, -1):
			if board[y][x] != null:
				if y != empty_y:
					var tile = board[y][x]
					board[empty_y][x] = tile
					board[y][x] = null
					tile.grid_pos = Vector2i(x, empty_y)

					var target_pos = Vector2(
						x * TILE_SIZE + x * TILE_GAP,
						empty_y * TILE_SIZE + empty_y * TILE_GAP
					)

					# Fixed travel time so all drops are consistent
					var travel_time = 0.2

					var tween = create_tween()
					tween.tween_property(tile, "position", target_pos, travel_time).set_trans(Tween.TRANS_LINEAR)

					# Tiny squash-and-stretch on landing
					var squash = create_tween()
					squash.tween_interval(travel_time) # start after landing
					squash.tween_property(tile, "scale", Vector2(1.1, 0.9), 0.05)
					squash.tween_property(tile, "scale", Vector2(1,1), 0.05)

				empty_y -= 1


func refill_tiles():

	# Spawn new tiles
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if board[y][x] == null:
				LETTER_FREQUENCY = _current_letter_counts()
				var letter := _pick_weighted_letter(LETTER_FREQUENCY)
				var pu := _roll_powerup()
				var tile = tile_scene.instantiate()
				tile.set_letter(letter, pu)

				tile.grid_pos = Vector2i(x, y)

				var target_pos = Vector2(
					x * TILE_SIZE + x * TILE_GAP,
					y * TILE_SIZE + y * TILE_GAP
				)

				var start_pos = Vector2(target_pos.x, -TILE_SIZE * (GRID_SIZE - y))
				tile.position = start_pos
				grid_node.add_child(tile)
				board[y][x] = tile

				# Fixed travel time so all new tiles fall at the same speed
				var travel_time = 0.2

				var tween = create_tween()
				tween.tween_property(tile, "position", target_pos, travel_time).set_trans(Tween.TRANS_LINEAR)

				# Tiny squash-and-stretch on landing
				var squash = create_tween()
				squash.tween_interval(travel_time)
				squash.tween_property(tile, "scale", Vector2(1.1, 0.9), 0.05)
				squash.tween_property(tile, "scale", Vector2(1,1), 0.05)
	wild_card_exists = false
	for row in board:
		for t in row:
			if t != null and is_instance_valid(t) and t.powerup == "wild_card":
				wild_card_exists = true
				break

				
func calculate_word_score(word: String) -> int:
	var n := word.length()
	if n < 3:
		return 0

	var base := 2**n * n

	# === DEBUG PRINT ===
	print("[ScoreCalc] Word:", word,
		" | Length:", n,
		" | BaseScore:", base)

	return int(base)


func game_over():
	timer_running = false
	StatsManager.record_game(score, words_found, longest_word)
	var elapsed = elapsed_time
	$GameOverUI.setup({
		"score": score,
		"best": StatsManager.data["high_score"],
		"words_found": words_found,
		"longest_word": longest_word if longest_word != "" else "-",
		"time": elapsed
	})


func _on_restart_button_pressed():
	restart_game() # Replace with function body.
	
func restart_game():
	# Reset game variables
	score = 0
	time_left = 60.0
	elapsed_time = 0.0
	timer_running = true
	combo = 0
	words_found = 0
	longest_word = ""

	# Reset UI
	$UI/ScoreLabel.text = "0"
	$UI/TimerLabel.text = "60"
	$UI/CurrentWordLabel.text = ""
	$GameOverUI.visible = false

	# Clear selection and board references
	selected_letters.clear()
 
	# Clear and regenerate the grid
	update_score_display()
	animate_score_change()
	clear_grid()
	generate_grid()
	ensure_playable_after_spawn()



func clear_grid():
	var grid = $Grid  # Adjust the path to your grid node

	# Free all existing tiles
	for child in grid.get_children():
		child.queue_free()

	# Clear board array
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			board[y][x] = null

		
func invalid_word_feedback(tiles: Array):
	for tile in tiles:
		var tween = create_tween()
		var original_pos = tile.position

		# Flash red
		tween.tween_property(tile, "modulate", Color(1, 0.3, 0.3), 0.05)

		# Shake left
		tween.tween_property(tile, "position", original_pos + Vector2(5, 0), 0.05)
		# Shake right
		tween.tween_property(tile, "position", original_pos - Vector2(5, 0), 0.05)
		# Back to center
		tween.tween_property(tile, "position", original_pos, 0.05)

		# Return color to normal
		tween.tween_property(tile, "modulate", Color(1, 1, 1), 0.05)
		
func update_current_word_display():
	var current_word := ""
	for tile in selected_letters:
		if tile.powerup == "wild_card":
			current_word += "★"   # or "_" or "★" if you want something fancier
		else:
			current_word += tile.letter
	$UI/CurrentWordLabel.text = current_word
