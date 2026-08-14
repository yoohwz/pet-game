class_name DomainState
extends RefCounted

const SCHEMA_VERSION := 7
const RelationshipModelScript = preload("res://domain/relationship/relationship_model.gd")
const MemoryModelScript = preload("res://domain/memory/memory_model.gd")
const ACTIVE_NONE := "NONE"
const ACTIVE_EGG := "EGG"
const ACTIVE_PET := "PET"
const LIFE_ALIVE := "ALIVE"
const LIFE_DEAD := "DEAD"
const GROWTH_NEWBORN := "NEWBORN"

static func new_profile(profile_id: String, created_at: int) -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "profile_id": profile_id, "created_at": created_at, "initial_egg_issued": false, "active_subject": ACTIVE_NONE, "active_egg": null, "active_pet": null, "memorial_count": 0, "memorials": [], "simulation": {"last_simulated_at": created_at, "clock_anomaly_count": 0, "simulation_version": 6, "balance_version": 1, "care_balance_version": 1, "survival_balance_version": 1, "growth_balance_version": 1}, "recent_events": []}

static func new_egg(egg_id: String, received_at: int, hatch_ready_at: int, shell_variant: String = "plain") -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "egg_id": egg_id, "received_at": received_at, "hatch_ready_at": hatch_ready_at, "state": "INCUBATING", "shell_variant": shell_variant, "interaction_summary": {"touch_count": 0, "last_interacted_at": null}, "hatching_started_at": null, "reserved_pet_id": null, "reserved_pet_seed": null}

static func new_pet(pet_id: String, name: String, born_at: int, seed: int) -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "identity": {"pet_id": pet_id, "name": name, "born_at": born_at, "seed": seed}, "life": {"life_state": LIFE_ALIVE, "growth_stage": GROWTH_NEWBORN, "newborn_protection_until": born_at, "died_at": null, "death_cause": ""}, "growth": {"growth_version":1, "growth_balance_version":1, "stage_started_at":born_at}, "activity": {"state": "AWAKE", "sleep_started_at": null}, "survival": {"condition": "STABLE", "critical_started_at": null}, "vitals": {"hunger": 100.0, "hydration": 100.0, "energy": 100.0, "hygiene": 100.0, "mood": 100.0, "health": 100.0}, "relationship": RelationshipModelScript.new_relationship(), "memory": MemoryModelScript.new_memory(), "personality": {"playfulness": 0.5, "curiosity": 0.5, "independence": 0.5, "attachment": 0.5, "food_motivation": 0.5, "touch_tolerance": 0.5, "activity_level": 0.5}}

static func validate_profile(profile: Dictionary) -> bool:
	if int(profile.get("schema_version", 0)) != SCHEMA_VERSION: return false
	if String(profile.get("profile_id", "")).is_empty(): return false
	var simulation: Dictionary = profile.get("simulation", {})
	if not (simulation.get("growth_balance_version") is int) or int(simulation.get("growth_balance_version", 0)) < 1: return false
	if not (profile.get("memorials", []) is Array) or int(profile.get("memorial_count", -1)) < profile.get("memorials", []).size(): return false
	for memorial in profile.get("memorials", []):
		if not validate_memorial(memorial): return false
	var active := String(profile.get("active_subject", ""))
	if profile.get("active_egg") != null and profile.get("active_pet") != null: return false
	if active == ACTIVE_NONE: return profile.get("active_egg") == null and profile.get("active_pet") == null
	if active == ACTIVE_EGG: return profile.get("active_pet") == null and profile.get("active_egg") is Dictionary and validate_egg(profile.active_egg)
	if active == ACTIVE_PET: return profile.get("active_egg") == null and profile.get("active_pet") is Dictionary and validate_pet(profile.active_pet)
	return false

static func validate_memorial(memorial: Variant) -> bool:
	if not (memorial is Dictionary): return false
	if String(memorial.get("memorial_id", "")).is_empty() or memorial.get("memorialized_at") == null: return false
	return memorial.get("pet_snapshot") is Dictionary and validate_pet(memorial.pet_snapshot) and String(memorial.pet_snapshot.get("life", {}).get("life_state", "")) == LIFE_DEAD

static func validate_egg(egg: Dictionary) -> bool:
	if egg.has("born_at") or String(egg.get("egg_id", "")).is_empty(): return false
	var state := String(egg.get("state", ""))
	if state not in ["INCUBATING", "READY", "HATCHING"]: return false
	if not egg.has("received_at") or not egg.has("hatch_ready_at"): return false
	if state == "HATCHING":
		var reserved_id = egg.get("reserved_pet_id")
		return reserved_id is String and not String(reserved_id).is_empty() and egg.get("reserved_pet_seed") != null and egg.get("hatching_started_at") != null
	return egg.get("hatching_started_at") == null and egg.get("reserved_pet_id") == null and egg.get("reserved_pet_seed") == null

static func validate_pet(pet: Dictionary) -> bool:
	var identity: Dictionary = pet.get("identity", {})
	var life: Dictionary = pet.get("life", {})
	if String(identity.get("pet_id", "")).is_empty() or not identity.has("born_at"): return false
	if String(life.get("life_state", "")) not in [LIFE_ALIVE, LIFE_DEAD]: return false
	if String(life.get("growth_stage", "")) not in ["NEWBORN", "CHILD", "ADOLESCENT", "ADULT"]: return false
	var growth: Dictionary = pet.get("growth", {})
	if not (growth.get("growth_version") is int) or int(growth.get("growth_version", 0)) != 1 or not (growth.get("growth_balance_version") is int) or int(growth.get("growth_balance_version", 0)) < 1 or not (growth.get("stage_started_at") is int) or int(growth.get("stage_started_at", -1)) < int(identity.get("born_at", 0)): return false
	if life.get("life_state") == LIFE_ALIVE and life.get("died_at") != null: return false
	var activity: Dictionary = pet.get("activity", {})
	if String(activity.get("state", "")) not in ["AWAKE", "SLEEPING"]: return false
	if (activity.state == "AWAKE" and activity.get("sleep_started_at") != null) or (activity.state == "SLEEPING" and activity.get("sleep_started_at") == null): return false
	var vitals: Dictionary = pet.get("vitals", {})
	for key in ["hunger", "hydration", "energy", "hygiene", "mood", "health"]:
		if not (vitals.get(key) is float or vitals.get(key) is int) or float(vitals.get(key)) < 0.0 or float(vitals.get(key)) > 100.0: return false
	var survival: Dictionary = pet.get("survival", {})
	if String(survival.get("condition", "")) not in ["STABLE", "CRITICAL"]: return false
	if life.life_state == LIFE_ALIVE and ((survival.condition == "STABLE" and survival.get("critical_started_at") != null) or (survival.condition == "CRITICAL" and survival.get("critical_started_at") == null)): return false
	if not _validate_relationship(pet.get("relationship", {})): return false
	if not _validate_memory(pet.get("memory", {})): return false
	if life.life_state == LIFE_ALIVE: return life.get("died_at") == null and String(life.get("death_cause", "")).is_empty()
	return life.get("died_at") != null and String(life.get("death_cause", "")) in ["STARVATION", "DEHYDRATION", "COMBINED_DEPRIVATION"] and float(vitals.health) == 0.0

static func _validate_relationship(relationship_value: Variant) -> bool:
	if not (relationship_value is Dictionary): return false
	var relationship: Dictionary = relationship_value
	if not (relationship.get("relationship_version") is int) or not (relationship.get("relationship_balance_version") is int) or int(relationship.get("relationship_version", 0)) != 1 or int(relationship.get("relationship_balance_version", 0)) < 1: return false
	for key in ["bond", "trust", "care_experience"]:
		if not (relationship.get(key) is int or relationship.get(key) is float): return false
	if float(relationship.bond) < 0 or float(relationship.bond) > 100 or float(relationship.trust) < 0 or float(relationship.trust) > 100 or float(relationship.care_experience) < 0: return false
	var rewarded: Variant = relationship.get("last_rewarded_at")
	if not (rewarded is Dictionary): return false
	for action in RelationshipModelScript.REWARD_ACTIONS:
		var at = rewarded.get(action)
		if at != null and not (at is int): return false
	return true

static func _validate_memory(memory_value: Variant) -> bool:
	if not (memory_value is Dictionary): return false
	var memory: Dictionary = memory_value
	if not (memory.get("memory_version") is int) or int(memory.get("memory_version", 0)) != 1 or not (memory.get("next_sequence") is int) or int(memory.next_sequence) < 0: return false
	var events_value = memory.get("events")
	if not (events_value is Array) or events_value.size() > 64: return false
	var seen_memory := {}; var seen_source := {}; var previous := -1
	for event_value in events_value:
		if not (event_value is Dictionary): return false
		var event: Dictionary = event_value
		for key in ["memory_id", "source_event_id", "sequence", "event_type", "occurred_at", "category", "valence", "importance", "details"]:
			if not event.has(key): return false
		if not (event.memory_id is String) or String(event.memory_id).is_empty() or not (event.source_event_id is String) or String(event.source_event_id).is_empty() or not (event.sequence is int) or int(event.sequence) < 0 or int(event.sequence) <= previous: return false
		if seen_memory.has(event.memory_id) or seen_source.has(event.source_event_id): return false
		if not (event.event_type is String) or String(event.event_type).is_empty() or not (event.occurred_at is int) or not (event.category is String) or String(event.category) not in ["CARE", "ROUTINE", "LIFECYCLE", "SURVIVAL"] or not (event.valence is int) or int(event.valence) not in [-1, 0, 1] or not (event.importance is int) or int(event.importance) < 0 or int(event.importance) > 4 or not (event.details is Dictionary): return false
		seen_memory[event.memory_id] = true; seen_source[event.source_event_id] = true; previous = int(event.sequence)
	if previous >= 0 and int(memory.next_sequence) <= previous: return false
	var routine: Variant = memory.get("routine")
	if not (routine is Dictionary): return false
	for action in MemoryModelScript.ROUTINE_ACTIONS:
		var item: Variant = routine.get(action)
		if not (item is Dictionary) or not (item.get("count") is int) or not (item.get("meaningful_count") is int) or int(item.get("count", -1)) < 0 or int(item.get("meaningful_count", -1)) < 0 or int(item.get("meaningful_count", 0)) > int(item.get("count", 0)): return false
		if item.get("last_at") != null and not (item.get("last_at") is int): return false
	var semantic: Variant = memory.get("semantic")
	if not (semantic is Dictionary): return false
	for key in ["care_interaction_count", "rescue_count", "critical_count"]:
		if not (semantic.get(key) is int) or int(semantic.get(key, -1)) < 0: return false
	return semantic.get("favorite_interaction") == null or String(semantic.get("favorite_interaction")) in MemoryModelScript.CARE_ACTIONS
