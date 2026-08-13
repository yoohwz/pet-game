class_name SimulationKernel
extends RefCounted

const DomainEventScript = preload("res://domain/simulation/domain_event.gd")

# Pure domain kernel: callers provide all timestamps; no wall-clock or node access.
static func simulate(profile: Dictionary, from_timestamp: int, to_timestamp: int, balance: Dictionary, lifecycle: Dictionary = {}, care: Dictionary = {}) -> Dictionary:
	var next: Dictionary = profile.duplicate(true)
	var elapsed: int = max(0, to_timestamp - from_timestamp)
	var simulation: Dictionary = next.get("simulation", {}).duplicate(true)
	if to_timestamp < from_timestamp:
		simulation["clock_anomaly_count"] = int(simulation.get("clock_anomaly_count", 0)) + 1
		simulation["last_simulated_at"] = from_timestamp
	else:
		simulation["last_simulated_at"] = to_timestamp
	next["simulation"] = simulation
	var subject := String(next.get("profile_id", "profile"))
	var generated_events: Array = []
	if String(next.get("active_subject", "NONE")) == "EGG":
		var egg: Dictionary = next.get("active_egg", {}).duplicate(true)
		subject = String(egg.get("egg_id", subject))
		if String(egg.get("state", "")) == "INCUBATING" and to_timestamp >= int(egg.get("hatch_ready_at", to_timestamp + 1)):
			egg["state"] = "READY"
			var ready_at := int(egg.get("hatch_ready_at"))
			generated_events.append(DomainEventScript.make("egg-ready:v3:%s:%d" % [subject, ready_at], "egg_ready", ready_at, subject, {}))
		next["active_egg"] = egg
	if String(next.get("active_subject", "NONE")) == "PET":
		var pet: Dictionary = next.get("active_pet", {}).duplicate(true)
		subject = String(pet.get("identity", {}).get("pet_id", subject))
		if String(pet.get("life", {}).get("life_state", "")) == "ALIVE":
			var vitals: Dictionary = pet.get("vitals", {}).duplicate(true)
			var sleeping := String(pet.get("activity", {}).get("state", "AWAKE")) == "SLEEPING"
			for key in ["hunger", "hydration", "hygiene"]:
				var duration := float(balance.get("%s_full_decay_seconds" % key, 0))
				if duration > 0.0: vitals[key] = clampf(float(vitals.get(key, 100.0)) - 100.0 * float(elapsed) / duration, 0.0, 100.0)
			var energy_duration := float(care.get("sleep_energy_full_recovery_seconds", 28800)) if sleeping else float(balance.get("energy_full_decay_seconds", 0))
			if energy_duration > 0.0: vitals["energy"] = clampf(float(vitals.get("energy", 100.0)) + (100.0 if sleeping else -100.0) * float(elapsed) / energy_duration, 0.0, 100.0)
			pet["vitals"] = vitals
		next["active_pet"] = pet
	var sim_version := int(simulation.get("simulation_version", 2))
	var balance_version := int(balance.get("balance_version", 1))
	var event := DomainEventScript.make("sim:v%d:b%d:%s:%d:%d" % [sim_version, balance_version, subject, from_timestamp, to_timestamp], "simulation_advanced", to_timestamp if elapsed > 0 else from_timestamp, subject, {"elapsed_seconds": elapsed})
	generated_events.append(event)
	return {"new_state": next, "generated_events": generated_events, "elapsed_seconds": elapsed}
