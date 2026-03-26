extends Control

const MAIN_SCENE  := "res://Scenes/main.tscn"
const DAILY_SCENE := "res://Scenes/daily.tscn"

@onready var play_button := $VBox/PlayButton
@onready var title_label := $VBox/TitleLabel
@onready var subtitle_label := $VBox/SubtitleLabel

func _ready():
	position = Vector2.ZERO
	size = get_viewport_rect().size
	
	# Animate title drop-in
	title_label.modulate.a = 0.0
	subtitle_label.modulate.a = 0.0
	play_button.modulate.a = 0.0

	var tween := create_tween().set_parallel(false)
	tween.tween_property(title_label, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property(subtitle_label, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_property(play_button, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE)

func _on_play_pressed():
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(MAIN_SCENE)
	)

func _on_daily_pressed():
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(DAILY_SCENE)
	)
