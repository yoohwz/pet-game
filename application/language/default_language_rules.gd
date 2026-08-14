class_name DefaultLanguageRules
extends RefCounted

const PATH := "res://data/language/language_rules_v1.json"

static func load_config() -> Dictionary:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null: return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
