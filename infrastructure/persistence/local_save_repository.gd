class_name LocalSaveRepository
extends RefCounted

const DomainStateScript = preload("res://domain/lifecycle/domain_state.gd")
const SaveMigratorScript = preload("res://infrastructure/persistence/save_migrator.gd")

const PROFILE_PATH := "user://profile.json"
const BACKUP_PATH := "user://backup/profile.json.bak"
const TEMP_PATH := "user://profile.json.tmp"

static func save_profile(profile: Dictionary) -> bool:
	if not DomainStateScript.validate_profile(profile): return false
	var serialized := JSON.stringify(profile, "\t")
	var parsed = JSON.parse_string(serialized)
	if not (parsed is Dictionary) or not DomainStateScript.validate_profile(parsed): return false
	DirAccess.make_dir_recursive_absolute("user://backup")
	var temp := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if temp == null: return false
	temp.store_string(serialized)
	temp.flush()
	temp.close()
	# Keep a known-good previous copy before replacing the canonical save.
	if FileAccess.file_exists(PROFILE_PATH):
		DirAccess.copy_absolute(PROFILE_PATH, BACKUP_PATH)
	var error := DirAccess.rename_absolute(TEMP_PATH, PROFILE_PATH)
	if error != OK:
		return false
	return true

static func load_profile() -> Dictionary:
	var primary := _read_valid(PROFILE_PATH)
	if not primary.is_empty(): return primary
	return _read_valid(BACKUP_PATH)

static func _read_valid(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var decoded = JSON.parse_string(file.get_as_text())
	file.close()
	if decoded is Dictionary:
		var migrated := SaveMigratorScript.migrate(decoded)
		if DomainStateScript.validate_profile(migrated): return migrated
	return {}
