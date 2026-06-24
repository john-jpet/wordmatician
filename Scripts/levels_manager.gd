extends Node

const SAVE_PATH := "user://levels_save.json"

var completed: Array = []      # indices where board was cleared (any words)
var star: Array      = []      # indices where all intended words were used
var current_level_idx: int = 0 # set before loading level.tscn

func _ready() -> void:
	_load()

func is_completed(idx: int) -> bool:
	return idx in completed

func is_star(idx: int) -> bool:
	return idx in star

func record_completion(idx: int) -> void:
	if not idx in completed:
		completed.append(idx)
		_save()

func record_star(idx: int) -> void:
	if not idx in star:
		star.append(idx)
	# star implies completed
	record_completion(idx)

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"completed": completed, "star": star}))
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return
	if parsed.has("completed"):
		completed = []
		for v in parsed["completed"]:
			completed.append(int(v))
	if parsed.has("star"):
		star = []
		for v in parsed["star"]:
			star.append(int(v))
