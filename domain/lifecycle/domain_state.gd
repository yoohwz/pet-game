class_name DomainState
extends RefCounted

const SCHEMA_VERSION := 2
const ACTIVE_NONE := "NONE"
const ACTIVE_EGG := "EGG"
const ACTIVE_PET := "PET"
const LIFE_ALIVE := "ALIVE"
const LIFE_DEAD := "DEAD"
const GROWTH_NEWBORN := "NEWBORN"

static func new_profile(profile_id: String, created_at: int) -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "profile_id": profile_id, "created_at": created_at, "active_subject": ACTIVE_NONE, "active_pet": null, "memorial_count": 0, "simulation": {"last_simulated_at": created_at, "clock_anomaly_count": 0, "simulation_version": 2, "balance_version": 1}, "recent_events": []}

static func new_egg(egg_id: String, received_at: int, hatch_ready_at: int, shell_variant: String = "plain") -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "egg_id": egg_id, "received_at": received_at, "hatch_ready_at": hatch_ready_at, "state": "INCUBATING", "shell_variant": shell_variant, "interaction_summary": {}}

static func new_pet(pet_id: String, name: String, born_at: int, seed: int) -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "identity": {"pet_id": pet_id, "name": name, "born_at": born_at, "seed": seed}, "life": {"life_state": LIFE_ALIVE, "growth_stage": GROWTH_NEWBORN, "newborn_protection_until": born_at, "died_at": null, "death_cause": ""}, "vitals": {"hunger": 100.0, "hydration": 100.0, "energy": 100.0, "hygiene": 100.0, "mood": 100.0, "health": 100.0}, "relationship": {"bond": 0.0, "trust": 0.0, "care_experience": 0.0}, "personality": {"playfulness": 0.5, "curiosity": 0.5, "independence": 0.5, "attachment": 0.5, "food_motivation": 0.5, "touch_tolerance": 0.5, "activity_level": 0.5}}

static func validate_profile(profile: Dictionary) -> bool:
	if int(profile.get("schema_version", 0)) != SCHEMA_VERSION: return false
	if String(profile.get("profile_id", "")).is_empty(): return false
	var active := String(profile.get("active_subject", ""))
	if active == ACTIVE_NONE: return profile.get("active_pet") == null
	if active == ACTIVE_PET: return profile.get("active_pet") is Dictionary and validate_pet(profile.active_pet)
	# Egg persistence deliberately remains a Phase 2 responsibility.
	return false

static func validate_pet(pet: Dictionary) -> bool:
	var identity: Dictionary = pet.get("identity", {})
	var life: Dictionary = pet.get("life", {})
	if String(identity.get("pet_id", "")).is_empty() or not identity.has("born_at"): return false
	if String(life.get("life_state", "")) not in [LIFE_ALIVE, LIFE_DEAD]: return false
	if String(life.get("growth_stage", "")) not in ["NEWBORN", "CHILD", "ADOLESCENT", "ADULT"]: return false
	if life.get("life_state") == LIFE_ALIVE and life.get("died_at") != null: return false
	return true
