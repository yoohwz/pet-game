class_name SimulationKernel
extends RefCounted

const DomainEventScript = preload("res://domain/simulation/domain_event.gd")

# Pure domain kernel: callers provide all timestamps; no wall-clock or node access.
static func simulate(profile: Dictionary, from_timestamp: int, to_timestamp: int) -> Dictionary:
	var next: Dictionary = profile.duplicate(true)
	var elapsed: int = max(0, to_timestamp - from_timestamp)
	var simulation: Dictionary = next.get("simulation", {}).duplicate(true)
	if to_timestamp < from_timestamp:
		simulation["clock_anomaly_count"] = int(simulation.get("clock_anomaly_count", 0)) + 1
		simulation["last_simulated_at"] = from_timestamp
	else:
		simulation["last_simulated_at"] = to_timestamp
	next["simulation"] = simulation
	# Proof value only: accumulated elapsed time is additive, so chunking is equivalent.
	next["foundation_elapsed_seconds"] = float(next.get("foundation_elapsed_seconds", 0.0)) + float(elapsed)
	var subject := String(next.get("active_subject", "NONE"))
	var event := DomainEventScript.make("sim:%s:%d:%d" % [subject, from_timestamp, to_timestamp], "simulation_advanced", to_timestamp if elapsed > 0 else from_timestamp, subject, {"elapsed_seconds": elapsed})
	return {"new_state": next, "generated_events": [event], "elapsed_seconds": elapsed}
