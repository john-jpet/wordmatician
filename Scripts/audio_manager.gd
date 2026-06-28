extends Node

var _players: Dictionary = {}
var _looping: Dictionary = {}  # keys that should loop continuously

func _ready() -> void:
	var sounds := {
		"select":       "res://Assets/Audio/select.mp3",
		"word_found":   "res://Assets/Audio/wordfound.mp3",
		"feature_word": "res://Assets/Audio/featureword.mp3",
		"mistake":      "res://Assets/Audio/mistake.mp3",
		"clock_tick":   "res://Assets/Audio/clocktick.mp3",
		"fanfare":      "res://Assets/Audio/fanfare.mp3",
		"bomb":         "res://Assets/Audio/bomb.mp3",
	}
	for key in sounds:
		var player := AudioStreamPlayer.new()
		player.stream = load(sounds[key])
		add_child(player)
		_players[key] = player

func _process(_delta: float) -> void:
	# Re-trigger looping sounds when they finish naturally
	for key in _looping:
		if _looping[key]:
			var player: AudioStreamPlayer = _players[key]
			if not player.playing:
				player.play()

func play(key: String) -> void:
	if _players.has(key):
		_looping[key] = false
		_players[key].play()

func play_loop(key: String) -> void:
	if _players.has(key):
		_looping[key] = true
		if not _players[key].playing:
			_players[key].play()

func stop(key: String) -> void:
	if _players.has(key):
		_looping[key] = false
		_players[key].stop()
