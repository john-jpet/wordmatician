extends Node2D
@onready var label := $Label

func show_text(text: String, color: Color = Color.WHITE):
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER

	# --- LabelSettings as its own resource we will tween directly ---
	var style := LabelSettings.new()
	style.font = preload("res://Assets/Exo2-Bold.ttf")
	style.font_size = 20
	style.outline_size = 24
	style.outline_color = Color(0.1, 0.2, 0.4, 0.55)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_offset = Vector2(0, 4)
	label.label_settings = style

	label.custom_minimum_size = Vector2(420, 0)
	#await get_tree().process_frame()
	label.pivot_offset = label.size * 0.5

	label.scale = Vector2.ONE
	label.modulate = color
	label.modulate.a = 1.0

	var tween := create_tween()

	# Animate in PARALLEL; chain set_trans/set_ease on the Tweener returned by tween_property(...)
	tween.parallel().tween_property(style, "font_size", 80, 0.20)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	tween.parallel().tween_property(self, "position:y", position.y - 40, 0.80)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.60)\
		.set_delay(0.20)

	# After the parallel block, do a small settle shrink
	tween.tween_property(style, "font_size", 28, 0.18)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	tween.finished.connect(queue_free)
