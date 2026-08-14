class_name DefaultGrowthBalance
extends RefCounted

const PATH := "res://data/balance/growth_v1.json"

static func load_config() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null: return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
