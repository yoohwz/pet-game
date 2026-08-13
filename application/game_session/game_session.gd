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

func _ready() -> void:
	balance = DefaultBalanceScript.load_balance()
	profile = LocalSaveRepositoryScript.load_profile()
	if profile.is_empty():
		var now := clock.wall_utc()
		profile = DomainStateScript.new_profile(_new_id("profile"), now)
		LocalSaveRepositoryScript.save_profile(profile)
	reconcile_to(clock.wall_utc())
	reanchor(clock.monotonic_seconds())

func reconcile_to(current_wall_time: int) -> Dictionary:
	var from_time := int(profile.get("simulation", {}).get("last_simulated_at", current_wall_time))
	var result := SimulationKernelScript.simulate(profile, from_time, current_wall_time, balance)
	profile = result.new_state
	_append_events(result.generated_events)
	LocalSaveRepositoryScript.save_profile(profile)
	return result

func advance_debug(seconds: int) -> Dictionary:
	var last := int(profile.get("simulation", {}).get("last_simulated_at", clock.wall_utc()))
	# Intentionally shares the same production reconciliation entry point.
	return reconcile_to(last + seconds)

func advance_active_to(monotonic_now: float) -> Dictionary:
	var effective := session_anchor_simulated_at + int(floor(monotonic_now - session_anchor_monotonic))
	var result := reconcile_to(effective)
	reanchor(monotonic_now)
	return result

func resume_at(wall_now: int, monotonic_now: float) -> Dictionary:
	var result := reconcile_to(wall_now)
	reanchor(monotonic_now)
	return result

func create_debug_pet(at_time: int) -> void:
	if String(profile.get("active_subject", "NONE")) != "NONE": return
	profile["active_subject"] = "PET"
	profile["active_pet"] = DomainStateScript.new_pet("debug-pet:%d" % at_time, "Debug Pet", at_time, at_time)
	profile["simulation"]["last_simulated_at"] = at_time
	LocalSaveRepositoryScript.save_profile(profile)
	reanchor(clock.monotonic_seconds())

func reset_debug_pet() -> void:
	if String(profile.get("active_subject", "")) != "PET": return
	profile["active_subject"] = "NONE"
	profile["active_pet"] = null
	LocalSaveRepositoryScript.save_profile(profile)

func reanchor(monotonic_now: float) -> void:
	session_anchor_simulated_at = int(profile.get("simulation", {}).get("last_simulated_at", 0))
	session_anchor_monotonic = monotonic_now

func _process(_delta: float) -> void:
	if profile.is_empty(): return
	var now := clock.monotonic_seconds()
	if now - session_anchor_monotonic >= 1.0: advance_active_to(now)
	if now - last_autosave_monotonic >= 30.0:
		LocalSaveRepositoryScript.save_profile(profile)
		last_autosave_monotonic = now

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		advance_active_to(clock.monotonic_seconds())
		LocalSaveRepositoryScript.save_profile(profile)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		resume_at(clock.wall_utc(), clock.monotonic_seconds())

func _append_events(events: Array) -> void:
	var recent: Array = profile.get("recent_events", [])
	for event in events: recent.append(event)
	while recent.size() > 10: recent.pop_front()
	profile["recent_events"] = recent

func _new_id(prefix: String) -> String:
	return "%s:%s" % [prefix, str(Time.get_ticks_usec())]
