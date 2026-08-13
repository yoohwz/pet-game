class_name DefaultLifecycle
extends RefCounted

const PATH := "res://data/lifecycle/egg_lifecycle_v1.json"

static func load_config() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null: return {}
	var value = JSON.parse_string(file.get_as_text())
	file.close()
	return value if value is Dictionary else {}
