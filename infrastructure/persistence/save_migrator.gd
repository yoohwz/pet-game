class_name SaveMigrator
extends RefCounted

const RelationshipModelScript = preload("res://domain/relationship/relationship_model.gd")
const MemoryModelScript = preload("res://domain/memory/memory_model.gd")

static func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("schema_version", 0))
	if version == 8: return _normalize_v8_integer_fields(data)
	if version == 7:
		var v8: Dictionary = data.duplicate(true); v8["schema_version"] = 8
		if v8.get("active_pet") is Dictionary: v8["active_pet"] = _migrate_pet_v8(v8.active_pet)
		if v8.get("active_egg") is Dictionary: v8.active_egg["schema_version"] = 8
		var memorials_v8: Array = []
		for memorial_value in v8.get("memorials", []):
			var memorial: Dictionary = memorial_value.duplicate(true)
			if memorial.get("pet_snapshot") is Dictionary: memorial["pet_snapshot"] = _migrate_pet_v8(memorial.pet_snapshot)
			memorials_v8.append(memorial)
		v8["memorials"] = memorials_v8
		return _normalize_v8_integer_fields(v8)
	if version == 6:
		var v7: Dictionary = data.duplicate(true); v7["schema_version"] = 7
		var s7: Dictionary = v7.get("simulation", {}).duplicate(true); s7["simulation_version"] = 6; s7["growth_balance_version"] = 1; v7["simulation"] = s7
		if v7.get("active_pet") is Dictionary: v7["active_pet"] = _migrate_pet_v7(v7.active_pet)
		if v7.get("active_egg") is Dictionary: v7.active_egg["schema_version"] = 7
		var v7_memorials: Array = []
		for memorial_value in v7.get("memorials", []):
			var memorial: Dictionary = memorial_value.duplicate(true)
			if memorial.get("pet_snapshot") is Dictionary: memorial["pet_snapshot"] = _migrate_pet_v7(memorial.pet_snapshot)
			v7_memorials.append(memorial)
		v7["memorials"] = v7_memorials
		return migrate(v7)
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
		return migrate(v6)
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

static func _migrate_pet_v7(pet: Dictionary) -> Dictionary:
	var next: Dictionary = pet.duplicate(true)
	next["schema_version"] = 7
	var born_at := int(next.get("identity", {}).get("born_at", 0))
	var existing_growth: Dictionary = next.get("growth", {})
	next["growth"] = {"growth_version":1, "growth_balance_version":1, "stage_started_at":int(existing_growth.get("stage_started_at", born_at)) if int(existing_growth.get("stage_started_at", born_at)) >= born_at else born_at}
	return next

static func _migrate_pet_v8(pet: Dictionary) -> Dictionary:
	var next: Dictionary = pet.duplicate(true)
	next["schema_version"] = 8
	var memory: Dictionary = next.get("memory", {}).duplicate(true)
	memory["memory_version"] = 2
	var semantic: Dictionary = memory.get("semantic", {}).duplicate(true)
	semantic["language"] = MemoryModelScript.new_language_semantic()
	memory["semantic"] = semantic
	next["memory"] = memory
	return next

# Godot's JSON parser represents numeric literals as floats. These fields are
# contractually integers, so canonicalize only exact whole values before domain
# validation. Fractional external data remains fractional and is rejected.
static func _normalize_v8_integer_fields(data: Dictionary) -> Dictionary:
	var next: Dictionary = data.duplicate(true)
	var simulation: Dictionary = next.get("simulation", {}).duplicate(true)
	simulation["growth_balance_version"] = _whole_int_or_original(simulation.get("growth_balance_version"))
	next["simulation"] = simulation
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
	if next.get("growth") is Dictionary:
		var growth: Dictionary = next.growth.duplicate(true)
		for key in ["growth_version", "growth_balance_version", "stage_started_at"]:
			growth[key] = _whole_int_or_original(growth.get(key))
		next["growth"] = growth
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
		if String(event.get("event_type", "")) == "pet_heard_message":
			var details: Dictionary = event.get("details", {}).duplicate(true)
			for key in ["language_version", "language_rules_version", "sentiment"]:
				details[key] = _whole_int_or_original(details.get(key))
			event["details"] = details
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
	if semantic.get("language") is Dictionary:
		var language: Dictionary = semantic.language.duplicate(true)
		for key in ["message_count", "repeated_message_count"]: language[key] = _whole_int_or_original(language.get(key))
		for count_key in ["intent_counts", "topic_counts"]:
			var counts: Dictionary = language.get(count_key, {}).duplicate(true)
			for key in counts.keys(): counts[key] = _whole_int_or_original(counts[key])
			language[count_key] = counts
		if language.get("last_message_at") != null: language["last_message_at"] = _whole_int_or_original(language.get("last_message_at"))
		semantic["language"] = language
	memory["semantic"] = semantic
	next["memory"] = memory
	return next

static func _whole_int_or_original(value: Variant) -> Variant:
	if value is float and value == floor(value): return int(value)
	return value
