class_name DomainState
extends RefCounted

const SCHEMA_VERSION := 5
const ACTIVE_NONE := "NONE"
const ACTIVE_EGG := "EGG"
const ACTIVE_PET := "PET"
const LIFE_ALIVE := "ALIVE"
const LIFE_DEAD := "DEAD"
const GROWTH_NEWBORN := "NEWBORN"

static func new_profile(profile_id: String, created_at: int) -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "profile_id": profile_id, "created_at": created_at, "initial_egg_issued": false, "active_subject": ACTIVE_NONE, "active_egg": null, "active_pet": null, "memorial_count": 0, "memorials": [], "simulation": {"last_simulated_at": created_at, "clock_anomaly_count": 0, "simulation_version": 5, "balance_version": 1, "care_balance_version": 1, "survival_balance_version": 1}, "recent_events": []}

static func new_egg(egg_id: String, received_at: int, hatch_ready_at: int, shell_variant: String = "plain") -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "egg_id": egg_id, "received_at": received_at, "hatch_ready_at": hatch_ready_at, "state": "INCUBATING", "shell_variant": shell_variant, "interaction_summary": {"touch_count": 0, "last_interacted_at": null}, "hatching_started_at": null, "reserved_pet_id": null, "reserved_pet_seed": null}

static func new_pet(pet_id: String, name: String, born_at: int, seed: int) -> Dictionary:
	return {"schema_version": SCHEMA_VERSION, "identity": {"pet_id": pet_id, "name": name, "born_at": born_at, "seed": seed}, "life": {"life_state": LIFE_ALIVE, "growth_stage": GROWTH_NEWBORN, "newborn_protection_until": born_at, "died_at": null, "death_cause": ""}, "activity": {"state": "AWAKE", "sleep_started_at": null}, "survival": {"condition": "STABLE", "critical_started_at": null}, "vitals": {"hunger": 100.0, "hydration": 100.0, "energy": 100.0, "hygiene": 100.0, "mood": 100.0, "health": 100.0}, "relationship": {"bond": 0.0, "trust": 0.0, "care_experience": 0.0}, "personality": {"playfulness": 0.5, "curiosity": 0.5, "independence": 0.5, "attachment": 0.5, "food_motivation": 0.5, "touch_tolerance": 0.5, "activity_level": 0.5}}

static func validate_profile(profile: Dictionary) -> bool:
	if int(profile.get("schema_version", 0)) != SCHEMA_VERSION: return false
	if String(profile.get("profile_id", "")).is_empty(): return false
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
	if life.life_state == LIFE_ALIVE: return life.get("died_at") == null and String(life.get("death_cause", "")).is_empty()
	return life.get("died_at") != null and String(life.get("death_cause", "")) in ["STARVATION", "DEHYDRATION", "COMBINED_DEPRIVATION"] and float(vitals.health) == 0.0
