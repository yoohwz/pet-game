class_name SaveMigrator
extends RefCounted

static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("schema_version", 0))
	if version == 2: return data
	if version != 1: return {}
	var migrated: Dictionary = data.duplicate(true)
	migrated["schema_version"] = 2
	migrated["active_pet"] = null
	migrated.erase("foundation_elapsed_seconds")
	var simulation: Dictionary = migrated.get("simulation", {}).duplicate(true)
	simulation["simulation_version"] = 2
	simulation["balance_version"] = 1
	migrated["simulation"] = simulation
	# Phase 0 never persisted an active pet/egg. Preserve a valid normal profile only.
	if String(migrated.get("active_subject", "NONE")) != "NONE": return {}
	return migrated
