class_name DefaultMemoryConfig
extends RefCounted

static func load_config() -> Dictionary:
	var file := FileAccess.open("res://data/config/memory_v1.json", FileAccess.READ)
	if file == null: return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
