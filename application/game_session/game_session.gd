class_name PetGameSession
extends Node

const ClockProviderScript = preload("res://application/game_session/clock_provider.gd")
const DomainStateScript = preload("res://domain/lifecycle/domain_state.gd")
const SimulationKernelScript = preload("res://domain/simulation/simulation_kernel.gd")
const LocalSaveRepositoryScript = preload("res://infrastructure/persistence/local_save_repository.gd")

var clock := ClockProviderScript.new()
var profile: Dictionary = {}
var session_started_monotonic := 0.0

func _ready() -> void:
	profile = LocalSaveRepositoryScript.load_profile()
	if profile.is_empty():
		var now := clock.wall_utc()
		profile = DomainStateScript.new_profile(_new_id("profile"), now)
		LocalSaveRepositoryScript.save_profile(profile)
	session_started_monotonic = clock.monotonic_seconds()

func reconcile_to(current_wall_time: int) -> Dictionary:
	var from_time := int(profile.get("simulation", {}).get("last_simulated_at", current_wall_time))
	var result := SimulationKernelScript.simulate(profile, from_time, current_wall_time)
	profile = result.new_state
	_append_events(result.generated_events)
	LocalSaveRepositoryScript.save_profile(profile)
	return result

func advance_debug(seconds: int) -> Dictionary:
	var last := int(profile.get("simulation", {}).get("last_simulated_at", clock.wall_utc()))
	# Intentionally shares the same production reconciliation entry point.
	return reconcile_to(last + seconds)

func _append_events(events: Array) -> void:
	var recent: Array = profile.get("recent_events", [])
	for event in events: recent.append(event)
	while recent.size() > 10: recent.pop_front()
	profile["recent_events"] = recent

func _new_id(prefix: String) -> String:
	return "%s:%s" % [prefix, str(Time.get_ticks_usec())]
