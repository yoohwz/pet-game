class_name LocalSaveRepository
extends RefCounted

const DomainStateScript = preload("res://domain/lifecycle/domain_state.gd")
const SaveMigratorScript = preload("res://infrastructure/persistence/save_migrator.gd")

const PROFILE_PATH := "user://profile.json"
const BACKUP_PATH := "user://backup/profile.json.bak"
const TEMP_PATH := "user://profile.json.tmp"
const BACKUP_TEMP_PATH := "user://backup/profile.json.bak.tmp"

# Narrow test-only seam: normal saves always use the real atomic rename path.
static var test_fail_next_primary_replace := false

static func save_profile(profile: Dictionary) -> bool:
	if not DomainStateScript.validate_profile(profile): return false
	var serialized := JSON.stringify(profile, "\t")
	var parsed = JSON.parse_string(serialized)
	if not (parsed is Dictionary) or not DomainStateScript.validate_profile(SaveMigratorScript.migrate(parsed)): return false
	if DirAccess.make_dir_recursive_absolute("user://backup") != OK: return false
	if FileAccess.file_exists(TEMP_PATH) and DirAccess.remove_absolute(TEMP_PATH) != OK: return false
	var temp := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if temp == null: return false
	temp.store_string(serialized)
	temp.flush()
	temp.close()
	# Establish that the on-disk temp is known-good before any replacement.
	if _read_valid(TEMP_PATH).is_empty():
		DirAccess.remove_absolute(TEMP_PATH)
		return false
	# Only a validated canonical file may rotate into backup. A corrupt primary must
	# never poison an existing valid backup.
	if not _read_valid(PROFILE_PATH).is_empty() and not _rotate_primary_to_backup():
		DirAccess.remove_absolute(TEMP_PATH)
		return false
	if not _replace_temp_with_primary():
		# A valid canonical or backup remains untouched and recoverable.
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

static func read_valid_profile(path: String) -> Dictionary:
	return _read_valid(path)

static func _rotate_primary_to_backup() -> bool:
	if FileAccess.file_exists(BACKUP_TEMP_PATH) and DirAccess.remove_absolute(BACKUP_TEMP_PATH) != OK:
		return false
	if DirAccess.copy_absolute(PROFILE_PATH, BACKUP_TEMP_PATH) != OK:
		return false
	if _read_valid(BACKUP_TEMP_PATH).is_empty():
		DirAccess.remove_absolute(BACKUP_TEMP_PATH)
		return false
	# rename is the only backup replacement operation; its error is checked before
	# canonical state is changed. Existing backup stays the recovery copy on failure.
	if DirAccess.rename_absolute(BACKUP_TEMP_PATH, BACKUP_PATH) != OK:
		return false
	return true

static func _replace_temp_with_primary() -> bool:
	if test_fail_next_primary_replace:
		test_fail_next_primary_replace = false
		return false
	return DirAccess.rename_absolute(TEMP_PATH, PROFILE_PATH) == OK
