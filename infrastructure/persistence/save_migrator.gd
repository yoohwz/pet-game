class_name SaveMigrator
extends RefCounted

const RelationshipModelScript = preload("res://domain/relationship/relationship_model.gd")
const MemoryModelScript = preload("res://domain/memory/memory_model.gd")

static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("schema_version", 0))
	if version == 6: return data
	if version == 5:
		var v6: Dictionary = data.duplicate(true); v6["schema_version"] = 6
		if v6.get("active_pet") is Dictionary: v6["active_pet"] = _migrate_pet(v6.active_pet)
		if v6.get("active_egg") is Dictionary: v6.active_egg["schema_version"] = 6
		var memorials: Array = []
		for memorial_value in v6.get("memorials", []):
			var memorial: Dictionary = memorial_value.duplicate(true)
			if memorial.get("pet_snapshot") is Dictionary: memorial["pet_snapshot"] = _migrate_pet(memorial.pet_snapshot)
			memorials.append(memorial)
		v6["memorials"] = memorials
		return v6
	if version == 4:
		var v5: Dictionary = data.duplicate(true); v5["schema_version"] = 5; v5["memorials"] = v5.get("memorials", [])
		var s5: Dictionary = v5.get("simulation", {}).duplicate(true); s5["simulation_version"] = 5; s5["survival_balance_version"] = 1; v5["simulation"] = s5
		if v5.get("active_pet") is Dictionary: v5.active_pet["survival"] = {"condition":"STABLE","critical_started_at":null}; v5.active_pet["schema_version"] = 5
		if v5.get("active_egg") is Dictionary: v5.active_egg["schema_version"] = 5
		return migrate(v5)
	if version == 3:
		var v4: Dictionary = data.duplicate(true); v4["schema_version"] = 4
		var s4: Dictionary = v4.get("simulation", {}).duplicate(true); s4["simulation_version"] = 4; s4["care_balance_version"] = 1; v4["simulation"] = s4
		if v4.get("active_pet") is Dictionary: v4.active_pet["activity"] = {"state":"AWAKE", "sleep_started_at":null}
		return migrate(v4)
	if version == 2:
		var v3: Dictionary = data.duplicate(true)
		v3["schema_version"] = 3
		v3["active_egg"] = null
		v3["initial_egg_issued"] = String(v3.get("active_subject", "NONE")) == "PET"
		var v3_sim: Dictionary = v3.get("simulation", {}).duplicate(true)
		v3_sim["simulation_version"] = 3
		v3["simulation"] = v3_sim
		return migrate(v3)
	if version != 1: return {}
	var migrated: Dictionary = data.duplicate(true)
	migrated["schema_version"] = 3
	migrated["active_pet"] = null
	migrated["active_egg"] = null
	migrated["initial_egg_issued"] = false
	migrated.erase("foundation_elapsed_seconds")
	var simulation: Dictionary = migrated.get("simulation", {}).duplicate(true)
	simulation["simulation_version"] = 3
	simulation["balance_version"] = 1
	migrated["simulation"] = simulation
	# Phase 0 never persisted an active pet/egg. Preserve a valid normal profile only.
	if String(migrated.get("active_subject", "NONE")) != "NONE": return {}
	return migrate(migrated)

static func _migrate_pet(pet: Dictionary) -> Dictionary:
	var next: Dictionary = pet.duplicate(true)
	next["schema_version"] = 6
	next["relationship"] = RelationshipModelScript.normalize(next.get("relationship", {}))
	next["memory"] = MemoryModelScript.new_memory()
	return next
