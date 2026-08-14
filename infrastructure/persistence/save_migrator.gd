class_name SaveMigrator
extends RefCounted

const RelationshipModelScript = preload("res://domain/relationship/relationship_model.gd")
const MemoryModelScript = preload("res://domain/memory/memory_model.gd")

static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("schema_version", 0))
	if version == 6: return _normalize_v6_integer_memory_fields(data)
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

# Godot's JSON parser represents numeric literals as floats. These fields are
# contractually integers, so canonicalize only exact whole values before domain
# validation. Fractional external data remains fractional and is rejected.
static func _normalize_v6_integer_memory_fields(data: Dictionary) -> Dictionary:
	var next: Dictionary = data.duplicate(true)
	if next.get("active_pet") is Dictionary:
		next["active_pet"] = _normalize_pet_memory_numbers(next.active_pet)
	var memorials: Array = []
	for memorial_value in next.get("memorials", []):
		var memorial: Dictionary = memorial_value.duplicate(true)
		if memorial.get("pet_snapshot") is Dictionary:
			memorial["pet_snapshot"] = _normalize_pet_memory_numbers(memorial.pet_snapshot)
		memorials.append(memorial)
	next["memorials"] = memorials
	return next

static func _normalize_pet_memory_numbers(pet: Dictionary) -> Dictionary:
	var next: Dictionary = pet.duplicate(true)
	if next.get("relationship") is Dictionary:
		var relationship: Dictionary = next.relationship.duplicate(true)
		for key in ["relationship_version", "relationship_balance_version"]:
			relationship[key] = _whole_int_or_original(relationship.get(key))
		var last_rewarded: Dictionary = relationship.get("last_rewarded_at", {}).duplicate(true)
		for action in last_rewarded.keys():
			if last_rewarded[action] != null: last_rewarded[action] = _whole_int_or_original(last_rewarded[action])
		relationship["last_rewarded_at"] = last_rewarded
		next["relationship"] = relationship
	if not (next.get("memory") is Dictionary): return next
	var memory: Dictionary = next.memory.duplicate(true)
	memory["memory_version"] = _whole_int_or_original(memory.get("memory_version"))
	memory["next_sequence"] = _whole_int_or_original(memory.get("next_sequence"))
	var events: Array = []
	for event_value in memory.get("events", []):
		var event: Dictionary = event_value.duplicate(true)
		for key in ["sequence", "occurred_at", "valence", "importance"]:
			event[key] = _whole_int_or_original(event.get(key))
		events.append(event)
	memory["events"] = events
	var routine: Dictionary = memory.get("routine", {}).duplicate(true)
	for action in routine.keys():
		if not (routine[action] is Dictionary): continue
		var item: Dictionary = routine[action].duplicate(true)
		for key in ["count", "meaningful_count", "last_at"]:
			if item.get(key) != null: item[key] = _whole_int_or_original(item.get(key))
		routine[action] = item
	memory["routine"] = routine
	var semantic: Dictionary = memory.get("semantic", {}).duplicate(true)
	for key in ["care_interaction_count", "rescue_count", "critical_count"]:
		semantic[key] = _whole_int_or_original(semantic.get(key))
	memory["semantic"] = semantic
	next["memory"] = memory
	return next

static func _whole_int_or_original(value: Variant) -> Variant:
	if value is float and value == floor(value): return int(value)
	return value
