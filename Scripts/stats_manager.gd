extends Node

const SAVE_PATH := "user://stats.json"

var data := {
	"high_score":      0,
	"games_played":    0,
	"total_words":     0,
	"longest_word":    "",
	"daily_cleared":   0,
}

func _ready() -> void:
	_load()

func record_game(score: int, words_found: int, longest: String) -> void:
	data["games_played"] += 1
	if score > int(data["high_score"]):
		data["high_score"] = score
	data["total_words"] = int(data["total_words"]) + words_found
	if longest.length() > String(data["longest_word"]).length():
		data["longest_word"] = longest
	_save()

func record_daily_clear() -> void:
	data["daily_cleared"] = int(data["daily_cleared"]) + 1
	_save()

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return
	for key in data.keys():
		if not parsed.has(key):
			continue
		# JSON deserializes all numbers as float; re-cast int fields
		if data[key] is int:
			data[key] = int(parsed[key])
		else:
			data[key] = parsed[key]
