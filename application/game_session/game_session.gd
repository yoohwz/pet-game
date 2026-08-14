class_name PetGameSession
extends Node

const ClockProviderScript = preload("res://application/game_session/clock_provider.gd")
const DomainStateScript = preload("res://domain/lifecycle/domain_state.gd")
const SimulationKernelScript = preload("res://domain/simulation/simulation_kernel.gd")
const LocalSaveRepositoryScript = preload("res://infrastructure/persistence/local_save_repository.gd")
const DefaultBalanceScript = preload("res://application/game_session/default_balance.gd")
const DefaultLifecycleScript = preload("res://application/lifecycle/default_lifecycle.gd")
const DefaultCareBalanceScript = preload("res://application/interaction/default_care_balance.gd")
const DefaultSurvivalBalanceScript = preload("res://application/game_session/default_survival_balance.gd")
const DefaultRelationshipBalanceScript = preload("res://application/relationship/default_relationship_balance.gd")
const DefaultMemoryConfigScript = preload("res://application/memory/default_memory_config.gd")
const DefaultGrowthBalanceScript = preload("res://application/growth/default_growth_balance.gd")
const DefaultLanguageRulesScript = preload("res://application/language/default_language_rules.gd")
const RelationshipModelScript = preload("res://domain/relationship/relationship_model.gd")
const MemoryModelScript = preload("res://domain/memory/memory_model.gd")
const LanguageModelScript = preload("res://domain/language/language_model.gd")

var clock := ClockProviderScript.new()
var profile: Dictionary = {}
var session_started_monotonic := 0.0
var session_anchor_simulated_at := 0
var session_anchor_monotonic := 0.0
var last_autosave_monotonic := 0.0
var balance: Dictionary = {}
var lifecycle: Dictionary = {}
var care: Dictionary = {}
var survival: Dictionary = {}
var relationship_balance: Dictionary = {}
var memory_config: Dictionary = {}
var growth: Dictionary = {}
var language_rules: Dictionary = {}
var id_rng := RandomNumberGenerator.new()
var persistence_write_count := 0 # Narrow observability seam for headless cadence tests.

func _ready() -> void:
	balance = DefaultBalanceScript.load_balance()
	lifecycle = DefaultLifecycleScript.load_config()
	care = DefaultCareBalanceScript.load_config()
	survival = DefaultSurvivalBalanceScript.load_config()
	relationship_balance = DefaultRelationshipBalanceScript.load_config()
	memory_config = DefaultMemoryConfigScript.load_config()
	growth = DefaultGrowthBalanceScript.load_config()
	language_rules = DefaultLanguageRulesScript.load_config()
	id_rng.randomize()
	initialize_session(clock.wall_utc(), clock.monotonic_seconds())

func initialize_session(wall_now: int, monotonic_now: float) -> void:
	id_rng.randomize()
	profile = LocalSaveRepositoryScript.load_profile()
	if profile.is_empty():
		profile = DomainStateScript.new_profile(_new_id("profile"), wall_now)
		_issue_initial_egg(profile, wall_now)
		persist_profile()
	else:
		if not bool(profile.get("initial_egg_issued", false)) and String(profile.get("active_subject", "NONE")) == "NONE":
			var issued: Dictionary = profile.duplicate(true)
			_issue_initial_egg(issued, wall_now)
			if save_candidate(issued): profile = issued
		reconcile_to(wall_now, true)
	reanchor(monotonic_now)
	last_autosave_monotonic = monotonic_now

func reconcile_to(current_wall_time: int, persist := true) -> Dictionary:
	var result := advance_in_memory_to(current_wall_time)
	if persist: persist_profile()
	return result

func advance_in_memory_to(target_time: int) -> Dictionary:
	var from_time := int(profile.get("simulation", {}).get("last_simulated_at", target_time))
	var result := SimulationKernelScript.simulate(profile, from_time, target_time, balance, lifecycle, care, survival, growth)
	profile = result.new_state
	_append_events(result.generated_events)
	return result

func persist_profile() -> bool:
	persistence_write_count += 1
	return LocalSaveRepositoryScript.save_profile(profile)

func save_candidate(candidate: Dictionary) -> bool:
	persistence_write_count += 1
	return LocalSaveRepositoryScript.save_profile(candidate)

func advance_debug(seconds: int, monotonic_now := -1.0) -> Dictionary:
	var last := int(profile.get("simulation", {}).get("last_simulated_at", clock.wall_utc()))
	var result := reconcile_to(last + seconds, true)
	reanchor(clock.monotonic_seconds() if monotonic_now < 0.0 else monotonic_now)
	return result

func advance_active_to(monotonic_now: float) -> Dictionary:
	var whole_seconds := int(floor(monotonic_now - session_anchor_monotonic))
	if whole_seconds <= 0: return {"new_state": profile, "generated_events": [], "elapsed_seconds": 0}
	var result := advance_in_memory_to(session_anchor_simulated_at + whole_seconds)
	# Advance both anchors by whole seconds: sub-second monotonic remainder survives.
	session_anchor_simulated_at += whole_seconds
	session_anchor_monotonic += whole_seconds
	return result

func resume_at(wall_now: int, monotonic_now: float) -> Dictionary:
	var result := reconcile_to(wall_now, true)
	reanchor(monotonic_now)
	return result

func create_debug_pet(at_time: int) -> void:
	if String(profile.get("active_subject", "NONE")) != "NONE": return
	profile["active_subject"] = "PET"
	profile["active_pet"] = DomainStateScript.new_pet("debug-pet:%d" % at_time, "Debug Pet", at_time, at_time)
	profile["simulation"]["last_simulated_at"] = at_time
	persist_profile()
	reanchor(clock.monotonic_seconds())

func reset_debug_pet() -> void:
	if String(profile.get("active_subject", "")) != "PET": return
	profile["active_subject"] = "NONE"
	profile["active_pet"] = null
	persist_profile()

func care_action(action: String, monotonic_now: float) -> Dictionary:
	advance_active_to(monotonic_now)
	if String(profile.get("active_subject", "")) != "PET": return {"ok":false,"reason":"NO_PET"}
	if String(profile.active_pet.life.get("life_state", "")) == "DEAD": return {"ok":false,"reason":"PET_DEAD"}
	var candidate: Dictionary = profile.duplicate(true)
	var pet: Dictionary = candidate.active_pet
	var before_vitals: Dictionary = pet.vitals.duplicate(true)
	var activity := String(pet.activity.get("state", "AWAKE"))
	if action != "wake" and activity == "SLEEPING": return {"ok":false,"reason":"PET_SLEEPING"}
	if action == "wake" and activity != "SLEEPING": return {"ok":false,"reason":"NOT_SLEEPING"}
	var key := ""; var delta := 0.0; var event_type := ""
	match action:
		"feed": key="hunger"; delta=float(care.feed_hunger_restore); event_type="pet_fed"
		"drink": key="hydration"; delta=float(care.drink_hydration_restore); event_type="pet_drank"
		"wash": key="hygiene"; delta=float(care.wash_hygiene_restore); event_type="pet_washed"
		"touch": key="mood"; delta=float(care.touch_mood_restore); event_type="pet_touched"
		"play":
			if float(pet.vitals.energy) < float(care.play_min_energy): return {"ok":false,"reason":"LOW_ENERGY"}
			pet.vitals.mood = clampf(float(pet.vitals.mood) + float(care.play_mood_restore), 0, 100); pet.vitals.energy = clampf(float(pet.vitals.energy) - float(care.play_energy_cost), 0, 100); event_type="pet_played"
		"sleep": pet.activity = {"state":"SLEEPING","sleep_started_at":int(candidate.simulation.last_simulated_at)}; event_type="pet_sleep_started"
		"wake": pet.activity = {"state":"AWAKE","sleep_started_at":null}; event_type="pet_woke"
		_: return {"ok":false,"reason":"UNKNOWN_ACTION"}
	if not key.is_empty(): pet.vitals[key] = clampf(float(pet.vitals[key]) + delta, 0, 100)
	var meaningful := action in ["touch", "play"] or (not key.is_empty() and float(pet.vitals[key]) > float(before_vitals.get(key, pet.vitals[key])))
	var at := int(candidate.simulation.last_simulated_at)
	var relationship_result := {"relationship":RelationshipModelScript.normalize(pet.get("relationship", {})), "deltas":{"bond":0.0,"trust":0.0,"care_experience":0.0,"rewarded":false}}
	if meaningful and action in RelationshipModelScript.REWARD_ACTIONS:
		relationship_result = RelationshipModelScript.apply_reward(pet.get("relationship", {}), action, at, relationship_balance)
	pet["relationship"] = relationship_result.relationship
	candidate.active_pet = pet
	var details := {"action":action, "meaningful":meaningful, "relationship_rewarded":bool(relationship_result.deltas.rewarded), "relationship_balance_version":int(relationship_balance.get("relationship_balance_version", 1)), "bond_delta":float(relationship_result.deltas.bond), "trust_delta":float(relationship_result.deltas.trust), "care_experience_delta":float(relationship_result.deltas.care_experience)}
	var primary_event := _application_event(event_type, at, pet.identity.pet_id, details)
	_append_event_to(candidate, primary_event)
	_project_pet_event(candidate, primary_event)
	pet = candidate.active_pet
	if String(pet.get("survival", {}).get("condition", "STABLE")) == "CRITICAL" and float(pet.vitals.hunger) > 0.0 and float(pet.vitals.hydration) > 0.0:
		var rescue := RelationshipModelScript.apply_rescue_bonus(pet.get("relationship", {}), relationship_balance)
		pet["survival"] = {"condition":"STABLE", "critical_started_at":null}
		pet["relationship"] = rescue.relationship
		candidate.active_pet = pet
		var stabilized := _application_event("pet_stabilized", at, pet.identity.pet_id, {"action":action, "bond_delta":float(rescue.deltas.bond), "trust_delta":float(rescue.deltas.trust), "care_experience_delta":float(rescue.deltas.care_experience), "relationship_balance_version":int(relationship_balance.get("relationship_balance_version", 1))})
		_append_event_to(candidate, stabilized)
		_project_pet_event(candidate, stabilized)
	if not save_candidate(candidate): return {"ok":false,"reason":"PERSIST_FAILED"}
	profile = candidate; last_autosave_monotonic = monotonic_now
	return {"ok":true,"reason":""}

func speak_to_pet(text: String, monotonic_now: float) -> Dictionary:
	advance_active_to(monotonic_now)
	if String(profile.get("active_subject", "")) != "PET": return {"ok":false,"reason":"NO_PET"}
	var pet: Dictionary = profile.active_pet
	if String(pet.get("life", {}).get("life_state", "")) == "DEAD": return {"ok":false,"reason":"PET_DEAD"}
	if String(pet.get("activity", {}).get("state", "")) == "SLEEPING": return {"ok":false,"reason":"PET_SLEEPING"}
	var understood: Dictionary = LanguageModelScript.understand(text, pet.get("memory", {}), language_rules)
	if not bool(understood.get("ok", false)): return {"ok":false,"reason":String(understood.get("reason", "EMPTY_MESSAGE"))}
	var candidate: Dictionary = profile.duplicate(true)
	var at := int(candidate.simulation.last_simulated_at)
	var payload: Dictionary = {"text":text,"normalized_text":understood.normalized_text,"intent":understood.intent,"topics":understood.topics,"sentiment":understood.sentiment,"reaction":understood.reaction,"memory_cue":understood.memory_cue,"language_version":1,"language_rules_version":int(understood.language_rules_version),"matched_rule_id":understood.matched_rule_id}
	var event := _application_event("pet_heard_message", at, String(candidate.active_pet.identity.pet_id), payload)
	_append_event_to(candidate, event)
	_project_pet_event(candidate, event)
	if not save_candidate(candidate): return {"ok":false,"reason":"PERSIST_FAILED"}
	profile = candidate; last_autosave_monotonic = monotonic_now
	understood["ok"] = true; understood["reason"] = ""; understood["event"] = event
	return understood

func memorialize_pet(monotonic_now: float) -> Dictionary:
	advance_active_to(monotonic_now)
	if String(profile.get("active_subject", "")) != "PET" or String(profile.get("active_pet", {}).get("life", {}).get("life_state", "")) != "DEAD": return {"ok":false,"reason":"PET_NOT_DEAD"}
	var candidate: Dictionary = profile.duplicate(true)
	var pet: Dictionary = candidate.active_pet
	var memorial_id := _new_durable_id("memorial")
	var at := int(candidate.simulation.last_simulated_at)
	var memorials: Array = candidate.get("memorials", []).duplicate(true)
	memorials.append({"schema_version":1, "memorial_id":memorial_id, "memorialized_at":at, "pet_snapshot":pet.duplicate(true)})
	candidate["memorials"] = memorials
	# `memorial_count` includes legacy memorial history that predates durable
	# snapshots, so it must not be recalculated from the snapshot array.
	candidate["memorial_count"] = int(candidate.get("memorial_count", 0)) + 1
	candidate["active_subject"] = "NONE"
	candidate["active_pet"] = null
	candidate["active_egg"] = null
	_append_event_to(candidate, _application_event("pet_memorialized", at, pet.identity.pet_id, {"memorial_id":memorial_id}))
	if not save_candidate(candidate): return {"ok":false,"reason":"PERSIST_FAILED"}
	profile = candidate
	last_autosave_monotonic = monotonic_now
	return {"ok":true,"reason":""}

func request_new_egg(monotonic_now: float) -> Dictionary:
	if String(profile.get("active_subject", "")) != "NONE" or int(profile.get("memorial_count", 0)) <= 0 or profile.get("memorials", []).is_empty(): return {"ok":false,"reason":"NEW_EGG_UNAVAILABLE"}
	var candidate: Dictionary = profile.duplicate(true)
	var at := int(candidate.simulation.last_simulated_at)
	_issue_initial_egg(candidate, at)
	candidate.active_egg.state = "INCUBATING"
	var recent: Array = candidate.get("recent_events", [])
	if not recent.is_empty(): recent[recent.size() - 1].payload = {"source":"new_cycle"}
	if not save_candidate(candidate): return {"ok":false,"reason":"PERSIST_FAILED"}
	profile = candidate
	reanchor(monotonic_now)
	last_autosave_monotonic = monotonic_now
	return {"ok":true,"reason":""}

func touch_egg(wall_now: int) -> bool:
	if String(profile.get("active_subject", "")) != "EGG": return false
	var state := String(profile.get("active_egg", {}).get("state", ""))
	if state not in ["INCUBATING", "READY"]: return false
	var candidate: Dictionary = profile.duplicate(true)
	var summary: Dictionary = candidate.active_egg.get("interaction_summary", {}).duplicate(true)
	summary["touch_count"] = int(summary.get("touch_count", 0)) + 1
	summary["last_interacted_at"] = wall_now
	candidate.active_egg["interaction_summary"] = summary
	_append_event_to(candidate, _application_event("egg_interacted", wall_now, candidate.active_egg.egg_id, {"touch_count": summary.touch_count}))
	if not save_candidate(candidate): return false
	profile = candidate
	return true

func begin_hatching(wall_now: int, monotonic_now: float) -> bool:
	if String(profile.get("active_subject", "")) != "EGG" or String(profile.get("active_egg", {}).get("state", "")) != "READY": return false
	var candidate: Dictionary = profile.duplicate(true)
	var egg: Dictionary = candidate.active_egg
	egg["state"] = "HATCHING"
	egg["hatching_started_at"] = max(wall_now, int(candidate.simulation.last_simulated_at))
	egg["reserved_pet_id"] = _new_durable_id("pet")
	egg["reserved_pet_seed"] = int(id_rng.randi())
	candidate["active_egg"] = egg
	_append_event_to(candidate, _application_event("hatching_started", int(egg.hatching_started_at), egg.egg_id, {"reserved_pet_id": egg.reserved_pet_id}))
	if not save_candidate(candidate): return false
	profile = candidate
	reanchor(monotonic_now)
	return true

func complete_hatching(wall_now: int, monotonic_now: float) -> bool:
	if String(profile.get("active_subject", "")) != "EGG" or String(profile.get("active_egg", {}).get("state", "")) != "HATCHING": return false
	var candidate: Dictionary = profile.duplicate(true)
	var egg: Dictionary = candidate.active_egg
	var born_at: int = max(wall_now, int(candidate.simulation.last_simulated_at))
	if wall_now < int(candidate.simulation.last_simulated_at): candidate.simulation.clock_anomaly_count = int(candidate.simulation.get("clock_anomaly_count", 0)) + 1
	var pet := DomainStateScript.new_pet(String(egg.reserved_pet_id), "Newborn", born_at, int(egg.reserved_pet_seed))
	pet.life.newborn_protection_until = born_at + int(lifecycle.get("newborn_protection_seconds", 43200))
	candidate["active_subject"] = "PET"
	candidate["active_egg"] = null
	candidate["active_pet"] = pet
	candidate.simulation.last_simulated_at = born_at
	var hatch_event := _application_event("pet_hatched", born_at, pet.identity.pet_id, {"egg_id": egg.egg_id, "born_at": born_at})
	_append_event_to(candidate, hatch_event)
	_project_pet_event(candidate, hatch_event)
	if not save_candidate(candidate): return false
	profile = candidate
	reanchor(monotonic_now)
	return true

func reanchor(monotonic_now: float) -> void:
	session_anchor_simulated_at = int(profile.get("simulation", {}).get("last_simulated_at", 0))
	session_anchor_monotonic = monotonic_now

func process_at(monotonic_now: float) -> void:
	if profile.is_empty(): return
	if monotonic_now - session_anchor_monotonic >= 1.0: advance_active_to(monotonic_now)
	if monotonic_now - last_autosave_monotonic >= 30.0:
		persist_profile()
		last_autosave_monotonic = monotonic_now

func pause_at(monotonic_now: float) -> void:
	advance_active_to(monotonic_now)
	persist_profile()

func _process(_delta: float) -> void:
	process_at(clock.monotonic_seconds())

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		pause_at(clock.monotonic_seconds())
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		resume_at(clock.wall_utc(), clock.monotonic_seconds())

func _append_events(events: Array) -> void:
	var recent: Array = profile.get("recent_events", [])
	for event in events:
		recent.append(event)
		_project_pet_event(profile, event)
	while recent.size() > 10: recent.pop_front()
	profile["recent_events"] = recent

func _append_event_to(target: Dictionary, event: Dictionary) -> void:
	var recent: Array = target.get("recent_events", [])
	recent.append(event)
	while recent.size() > 10: recent.pop_front()
	target["recent_events"] = recent

func _project_pet_event(target: Dictionary, event: Dictionary) -> void:
	if String(target.get("active_subject", "")) != "PET" or not (target.get("active_pet") is Dictionary): return
	var pet: Dictionary = target.active_pet
	if String(event.get("subject_id", "")) != String(pet.get("identity", {}).get("pet_id", "")): return
	pet["memory"] = MemoryModelScript.project(pet.get("memory", MemoryModelScript.new_memory()), event, memory_config)
	target["active_pet"] = pet

func _issue_initial_egg(target: Dictionary, wall_now: int) -> void:
	target["initial_egg_issued"] = true
	target["active_subject"] = "EGG"
	target["active_egg"] = DomainStateScript.new_egg(_new_durable_id("egg"), wall_now, wall_now + int(lifecycle.get("initial_incubation_seconds", 14400)))
	target["active_pet"] = null
	_append_event_to(target, _application_event("egg_received", wall_now, target.active_egg.egg_id, {}))

func _application_event(event_type: String, at: int, subject_id: String, payload: Dictionary) -> Dictionary:
	return {"schema_version": 1, "event_id": _new_durable_id("evt"), "event_type": event_type, "occurred_at": at, "subject_id": subject_id, "payload": payload}

func _new_id(prefix: String) -> String:
	return _new_durable_id(prefix)

func _new_durable_id(prefix: String) -> String:
	return "%s:%08x%08x" % [prefix, id_rng.randi(), id_rng.randi()]
