extends Node2D

@onready var sprite: Sprite2D = $Sprite2D
@onready var area: Area2D = $Area2D

var letter: String = ""
var grid_pos: Vector2i
var powerup: String = "none"

var amplitude := 0.1   # how much to scale
var speed := 1.5       # how fast to pulse

var hue_shift := 0.0         # for rainbow shimmer
var hue_speed := 0.1         # how fast the colors cycle
var has_rainbow_glow := false

func _process(delta):
	if powerup == "bomb":
		var main = get_tree().root.get_node("Main")  # adjust to your actual main node path
		if main and main.has_method("_process"):  # sanity check
			var t = main.global_time
			var scale_val = 1.0 + amplitude * sin(t * speed)
			sprite.scale = Vector2(scale_val, scale_val)
			var color_scale = 0.4 * sin(t * speed)
			if color_scale < 0:
				color_scale = 0
			sprite.modulate = Color(1.0 + color_scale, 1.0, 1.0)
	elif powerup == "wild_card":
		# --- WILD CARD ANIMATION ---
		hue_shift = fmod(hue_shift + delta * hue_speed, 1.0)
		var rainbow_color = Color.from_hsv(hue_shift, 0.8, 1.0)
		sprite.modulate = rainbow_color

		if has_rainbow_glow:
			var glow = $Glow
			glow.modulate = rainbow_color
			glow.modulate.a = 0.5


# --- Called by main.gd when spawning tiles ---
func set_letter(l: String, pu: String = "none") -> void:
	letter = l
	powerup = pu

	var lbl = null
	if has_node("Label"):
		lbl = $Label
	if lbl:
		lbl.text = l

		# --- Apply font and styling ---
		var style = LabelSettings.new()
		style.font = preload("res://Assets/Exo2-Bold.ttf")  # <-- your font
		style.font_size = 72  # scale to your tile size

		style.font_color = Color(1, 1, 1)
		style.outline_color = Color(0.1, 0.2, 0.4, 0.3)
		style.outline_size = 25
		style.shadow_color = Color(0, 0, 0, 0.3)
		style.shadow_offset = Vector2(5, 5)
		

		lbl.label_settings = style
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_update_visual()


# --- Update visuals based on powerup type ---
func _update_visual() -> void:
	if !is_instance_valid(sprite):
		await ready  # wait until _ready() is done
	# or alternatively: return until next frame
	# await get_tree().process_frame
	match powerup:
		"x2":
			sprite.texture = preload("res://Assets/goldtile.png")
			_add_powerup_glow(Color(1.0, 0.9, 0.3))  # gold
		"x3":
			sprite.texture = preload("res://Assets/amethysttile.png")
			_add_powerup_glow(Color(0.46, 0.18, 0.83))  # amethyst
		"bomb":
			sprite.texture = preload("res://Assets/bombtile.png")
			_add_powerup_glow(Color(1.0, 0.2, 0.2))  # red
		"wild_card":
			sprite.texture = preload("res://Assets/wildtile.png")
			$Label.text = "★"
			#_add_powerup_glow(Color(1.0, 1.0, 1.0))  # neutral white

			



		_:
			_remove_glow()
			has_rainbow_glow = false


func _add_powerup_glow(color: Color) -> void:
	if has_node("Glow"):
		$Glow.queue_free()

	var glow := Sprite2D.new()
	glow.name = "Glow"

	if $Sprite2D and $Sprite2D.texture:
		glow.texture = $Sprite2D.texture.duplicate()

	glow.modulate = color
	glow.scale = Vector2(1.15, 1.15)
	glow.modulate.a = 0.3
	glow.show_behind_parent = true
	glow.z_index = -100   # force it far behind everything

	add_child(glow)
	move_child(glow, 0)   # ensure it’s the first child in draw order

func _remove_glow() -> void:
	if has_node("Glow"):
		$Glow.queue_free()


func _on_area_2d_input_event(viewport, event, shape_idx):
	if event is InputEventMouseButton and event.pressed:
		if get_parent().get_parent().has_method("letter_tapped"):
			get_parent().get_parent().letter_tapped(self)
