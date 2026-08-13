class_name DefaultCareBalance
extends RefCounted
static func load_config() -> Dictionary:
	var f := FileAccess.open("res://data/balance/pet_care_v1.json", FileAccess.READ)
	if f == null: return {}
	var v = JSON.parse_string(f.get_as_text()); f.close()
	return v if v is Dictionary else {}
