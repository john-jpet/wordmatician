extends Node2D

@onready var grid_node := $Grid
var popup_scene := preload("res://Scenes/pop_up_text.tscn")
@onready var popup_layer := $UI/PopupLayer
var active_popups: Array = []


const GRID_SIZE := 5
const TILE_SIZE := 128          # size of each tile (px)
const TILE_GAP  := 12          # gap between tiles (px)
# If you have a top UI bar and want the grid centered in the remaining space, set this.
# Otherwise leave 0 to center in the whole screen.
const UI_TOP_RESERVED := 0

var global_time := 0.0
var board: Array = []
var tile_scene := preload("res://Scenes/letter_tile.tscn")
var selected_letters = []
var dictionary = {}
var score: int = 0
var combo: int = 0
var base_points: int = 1  # starting value for scoring

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

const VOWEL_MULTIPLIER := 1.25  # boost vowels a bit more for QoL
var _cdf: PackedFloat32Array = []
var _letters: PackedStringArray = []
var _total_weight := 0.0

var time_left: float = 60.0  # start with 60 seconds
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


func _ready():
	var settings = LabelSettings.new()
	#settings.outline_size = 20
	#settings.outline_color = Color(0, 0.3, 0.8, 1)  # soft blue outline
	settings.font = preload("res://Assets/Exo2-Bold.ttf")  # <-- your font
	settings.shadow_size = 20
	settings.shadow_color = Color(0, 0, 0, 0.4)
	settings.font_size = 100
	
	score_label.label_settings = settings
	
	randomize()
	_build_weight_cdf()
	_center_grid()
	generate_grid()
	load_dictionary()
	create_buttons()
	$UI/CurrentWordLabel.text = ""



func create_submit_button() -> TextureButton:
	var button := TextureButton.new()
	button.texture_normal = load("res://Assets/checkmark.png")
	button.texture_hover = button.texture_normal
	button.texture_pressed = button.texture_normal

	#button.expand = true
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

func create_buttons():
	# === Submit Button ===
	var submit_button = create_submit_button()
	submit_button.name = "SubmitButton"
	submit_button.pivot_offset = submit_button.size / 2

	$UI.add_child(submit_button)

	var screen_size = get_viewport_rect().size
	# === Cancel Button ===
	var cancel_button := create_cancel_button()
	cancel_button.name = "CancelButton"
	

	$UI.add_child(cancel_button)


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
			popup.show_text("Multiplier! x%d" % value, Color.ORANGE)
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
		time_left -= delta
		if time_left <= 0:
			time_left = 0
			timer_running = false
			stop_timer_warning()
			game_over()

		$UI/TimerLabel.text = " %d" % ceil(time_left)
		$UI/ScoreLabel.text = str(displayed_score)
		

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
	var origin_x = (screen.x - grid_px.x) / 2.0 + (TILE_SIZE / 2)
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
			var letter := _pick_weighted_letter()
			#var pu := _roll_powerup()
			var tile = tile_scene.instantiate()
			tile.set_letter(letter, "none")

			tile.grid_pos = Vector2i(x, y)

			# Position relative to the Grid node (which we center)
			var local_x = x * (TILE_SIZE + TILE_GAP)
			var local_y = y * (TILE_SIZE + TILE_GAP)
			tile.position = Vector2(local_x, local_y)

			grid_node.add_child(tile)
			row.append(tile)
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

func _pick_weighted_letter() -> String:
	var r = randf() * _total_weight
	for i in _cdf.size():
		if r <= _cdf[i]:
			return _letters[i]
	# Fallback (shouldn't hit)
	return _letters[_letters.size() - 1]


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
func _unhandled_input(event):
	if event.is_action_pressed("ui_accept"):
		check_word()



func check_word():
	var word := ""
	var word_mult := 0.0
	var has_bomb := false
	var has_wild := false
	var popup_final_mult := 1
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
	if word.length() > 2:
		if has_wild:
			var re := RegEx.new()
			re.compile("^" + word + "$")
			for key in dictionary.keys():
				if key.length() == word.length() and re.search(key):
					valid = true
					break
		else:
			valid = dictionary.has(word)

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
	var COMBO_BONUS := 0
	if combo < 10:
		COMBO_BONUS = (1 + combo * 0.1)
		points_to_add = int(points_to_add * COMBO_BONUS)
	else:
		COMBO_BONUS = 2
		points_to_add *= COMBO_BONUS
		
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

	# Popups (show once)
	if word.length() > 4:
		show_bonus_popup("length", word.length())
	if combo > 1:
		show_bonus_popup("combo", combo)
	if popup_mult_to_show > 1:
		show_bonus_popup("multiplier", popup_mult_to_show)

	# Reset selection + label
	selected_letters.clear()
	$UI/CurrentWordLabel.text = ""

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

		# 🔁 Use cross/3x3 area instead of fixed 3x3 neighbors
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

# Base points per tile destroyed by the bomb (no multipliers here)
func _bomb_tile_points_base(tile) -> int:
	var base := 5
	return base


# Sum bomb points only from the explosion dictionary (no multipliers here)
func _sum_explosion_points(explosion_dict: Dictionary) -> int:
	var sum := 0
	for k in explosion_dict.keys():
		var t = explosion_dict[k]
		if t != null and is_instance_valid(t):
			sum += _bomb_tile_points_base(t)
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

	# --- 6. Collapse and refill the grid ---
	await get_tree().create_timer(0.25).timeout
	drop_tiles()
	refill_tiles()

func remove_selected():
	print("Removing selected tiles:", selected_letters.size())
	for tile in selected_letters:
		print(" -", tile.letter, tile.grid_pos, tile.powerup)
		board[tile.grid_pos.y][tile.grid_pos.x] = null
		remove_tile(tile)
	selected_letters.clear()
	
	drop_tiles()
	refill_tiles()

	
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
	var max_y = 0
	var tiles_to_spawn = []

	# Spawn new tiles
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if board[y][x] == null:
				var letter := _pick_weighted_letter()
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
	$GameOverUI.visible = true
	$GameOverUI/ColorRect/VBoxContainer/FinalScoreLabel.text = "Score: %d" % (score)


func _on_restart_button_pressed():
	restart_game() # Replace with function body.
	
func restart_game():
	# Reset game variables
	score = 0
	time_left = 60.0
	timer_running = true
	combo = 0

	# Reset UI
	$UI/ScoreLabel.text = "0"
	#$UI/ComboLabel.text = "0"
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
