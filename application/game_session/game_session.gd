class_name PetGameSession
extends Node

const ClockProviderScript = preload("res://application/game_session/clock_provider.gd")
const DomainStateScript = preload("res://domain/lifecycle/domain_state.gd")
const SimulationKernelScript = preload("res://domain/simulation/simulation_kernel.gd")
const LocalSaveRepositoryScript = preload("res://infrastructure/persistence/local_save_repository.gd")
const DefaultBalanceScript = preload("res://application/game_session/default_balance.gd")

var clock := ClockProviderScript.new()
var profile: Dictionary = {}
var session_started_monotonic := 0.0
var session_anchor_simulated_at := 0
var session_anchor_monotonic := 0.0
var last_autosave_monotonic := 0.0
var balance: Dictionary = {}
var persistence_write_count := 0 # Narrow observability seam for headless cadence tests.

func _ready() -> void:
	balance = DefaultBalanceScript.load_balance()
	initialize_session(clock.wall_utc(), clock.monotonic_seconds())

func initialize_session(wall_now: int, monotonic_now: float) -> void:
	profile = LocalSaveRepositoryScript.load_profile()
	if profile.is_empty():
		profile = DomainStateScript.new_profile(_new_id("profile"), wall_now)
		persist_profile()
	reconcile_to(wall_now, true)
	reanchor(monotonic_now)
	last_autosave_monotonic = monotonic_now

func reconcile_to(current_wall_time: int, persist := true) -> Dictionary:
	var result := advance_in_memory_to(current_wall_time)
	if persist: persist_profile()
	return result

func advance_in_memory_to(target_time: int) -> Dictionary:
	var from_time := int(profile.get("simulation", {}).get("last_simulated_at", target_time))
	var result := SimulationKernelScript.simulate(profile, from_time, target_time, balance)
	profile = result.new_state
	_append_events(result.generated_events)
	return result

func persist_profile() -> bool:
	persistence_write_count += 1
	return LocalSaveRepositoryScript.save_profile(profile)

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
	for event in events: recent.append(event)
	while recent.size() > 10: recent.pop_front()
	profile["recent_events"] = recent

func _new_id(prefix: String) -> String:
	return "%s:%s" % [prefix, str(Time.get_ticks_usec())]
