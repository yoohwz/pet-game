class_name SimulationKernel
extends RefCounted

const DomainEventScript = preload("res://domain/simulation/domain_event.gd")
const GrowthModelScript = preload("res://domain/growth/growth_model.gd")

# Pure domain kernel: callers provide all timestamps; no wall-clock or node access.
static func simulate(profile: Dictionary, from_timestamp: int, to_timestamp: int, balance: Dictionary, lifecycle: Dictionary = {}, care: Dictionary = {}, survival: Dictionary = {}, growth: Dictionary = {}) -> Dictionary:
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
			var survival_result := _simulate_pet_survival(pet, from_timestamp, to_timestamp, balance, care, survival, subject)
			pet = survival_result.pet
			var growth_result := GrowthModelScript.transitions_to(pet, int(survival_result.biological_to), growth, int(simulation.get("simulation_version", 6)))
			pet = growth_result.pet
			generated_events.append_array(growth_result.events)
			generated_events.append_array(survival_result.events)
		next["active_pet"] = pet
	var sim_version := int(simulation.get("simulation_version", 2))
	var balance_version := int(balance.get("balance_version", 1))
	# Identity reflects the care configuration that actually produced this result.
	var care_version := int(care.get("care_balance_version", simulation.get("care_balance_version", 1)))
	var survival_version := int(survival.get("survival_balance_version", simulation.get("survival_balance_version", 1)))
	var growth_version := int(growth.get("growth_balance_version", simulation.get("growth_balance_version", 1)))
	generated_events.sort_custom(func(a, b):
		if int(a.occurred_at) != int(b.occurred_at): return int(a.occurred_at) < int(b.occurred_at)
		return _biological_event_order(String(a.event_type)) < _biological_event_order(String(b.event_type))
	)
	var event := DomainEventScript.make("sim:v%d:b%d:c%d:s%d:g%d:%s:%d:%d" % [sim_version, balance_version, care_version, survival_version, growth_version, subject, from_timestamp, to_timestamp], "simulation_advanced", to_timestamp if elapsed > 0 else from_timestamp, subject, {"elapsed_seconds": elapsed})
	generated_events.append(event)
	return {"new_state": next, "generated_events": generated_events, "elapsed_seconds": elapsed}

# Integrates only at semantic boundaries. All whole-second transition timestamps are
# derived from the same linear need curves, so splitting an interval cannot change them.
static func _simulate_pet_survival(pet: Dictionary, from_time: int, to_time: int, balance: Dictionary, care: Dictionary, survival: Dictionary, subject: String) -> Dictionary:
	var events: Array = []
	if to_time <= from_time: return {"pet": pet, "events": events, "biological_to": to_time}
	var starting_vitals: Dictionary = pet.get("vitals", {}).duplicate(true)
	var life: Dictionary = pet.get("life", {}).duplicate(true)
	var survival_state: Dictionary = pet.get("survival", {}).duplicate(true)
	var hunger_zero_at := _zero_time(float(starting_vitals.get("hunger", 100.0)), float(balance.get("hunger_full_decay_seconds", 0.0)), from_time)
	var hydration_zero_at := _zero_time(float(starting_vitals.get("hydration", 100.0)), float(balance.get("hydration_full_decay_seconds", 0.0)), from_time)
	var protection_until := int(life.get("newborn_protection_until", from_time))
	var boundaries: Array[int] = [from_time, to_time]
	for boundary in [protection_until, hunger_zero_at, hydration_zero_at]:
		if boundary > from_time and boundary < to_time: boundaries.append(boundary)
	boundaries.sort()
	var health := float(starting_vitals.get("health", 100.0))
	var critical_threshold := float(survival.get("critical_health_threshold", 25.0))
	var death_at := -1
	for index in range(boundaries.size() - 1):
		var segment_start: int = boundaries[index]
		var segment_end: int = boundaries[index + 1]
		var rate := _damage_rate(segment_start, protection_until, hunger_zero_at, hydration_zero_at, survival)
		if rate <= 0.0: continue
		if String(survival_state.get("condition", "STABLE")) == "STABLE" and health - rate * float(segment_end - segment_start) <= critical_threshold:
			var critical_at := segment_start if health <= critical_threshold else segment_start + _whole_seconds_to_loss(health - critical_threshold, rate)
			survival_state = {"condition":"CRITICAL", "critical_started_at":critical_at}
			events.append(DomainEventScript.make("critical:v5:s%d:%s:%d" % [int(survival.get("survival_balance_version", 1)), subject, critical_at], "pet_became_critical", critical_at, subject, {}))
		if health - rate * float(segment_end - segment_start) <= 0.0:
			death_at = segment_start + _whole_seconds_to_loss(health, rate)
			break
		health -= rate * float(segment_end - segment_start)
	var biological_to: int = death_at if death_at >= 0 else to_time
	var elapsed: int = max(0, biological_to - from_time)
	var vitals := _advance_vitals(starting_vitals, elapsed, balance, care, String(pet.get("activity", {}).get("state", "AWAKE")) == "SLEEPING")
	vitals["health"] = 0.0 if death_at >= 0 else clampf(health, 0.0, 100.0)
	if death_at >= 0:
		life["life_state"] = "DEAD"
		life["died_at"] = death_at
		var hunger_zero := death_at >= hunger_zero_at
		var hydration_zero := death_at >= hydration_zero_at
		life["death_cause"] = "COMBINED_DEPRIVATION" if hunger_zero and hydration_zero else ("STARVATION" if hunger_zero else "DEHYDRATION")
		events.append(DomainEventScript.make("death:v5:s%d:%s:%d:%s" % [int(survival.get("survival_balance_version", 1)), subject, death_at, life.death_cause], "pet_died", death_at, subject, {"death_cause":life.death_cause, "died_at":death_at}))
	pet["vitals"] = vitals
	pet["life"] = life
	pet["survival"] = survival_state
	return {"pet": pet, "events": events, "biological_to": biological_to}

static func _biological_event_order(event_type: String) -> int:
	return {"pet_grew":0, "pet_became_critical":1, "pet_died":2}.get(event_type, 3)

static func _advance_vitals(start: Dictionary, elapsed: int, balance: Dictionary, care: Dictionary, sleeping: bool) -> Dictionary:
	var vitals: Dictionary = start.duplicate(true)
	for key in ["hunger", "hydration", "hygiene"]:
		var duration := float(balance.get("%s_full_decay_seconds" % key, 0.0))
		if duration > 0.0: vitals[key] = clampf(float(vitals.get(key, 100.0)) - 100.0 * float(elapsed) / duration, 0.0, 100.0)
	var energy_duration := float(care.get("sleep_energy_full_recovery_seconds", 28800.0)) if sleeping else float(balance.get("energy_full_decay_seconds", 0.0))
	if energy_duration > 0.0: vitals["energy"] = clampf(float(vitals.get("energy", 100.0)) + (100.0 if sleeping else -100.0) * float(elapsed) / energy_duration, 0.0, 100.0)
	return vitals

static func _zero_time(value: float, full_decay_seconds: float, from_time: int) -> int:
	if value <= 0.0: return from_time
	if full_decay_seconds <= 0.0: return 2147483647
	return from_time + int(ceil(value * full_decay_seconds / 100.0))

static func _damage_rate(at_time: int, protection_until: int, hunger_zero_at: int, hydration_zero_at: int, survival: Dictionary) -> float:
	if at_time < protection_until: return 0.0
	var rate := 0.0
	if at_time >= hunger_zero_at: rate += float(survival.get("hunger_zero_health_loss_per_hour", 2.0)) / 3600.0
	if at_time >= hydration_zero_at: rate += float(survival.get("hydration_zero_health_loss_per_hour", 4.0)) / 3600.0
	return rate

static func _whole_seconds_to_loss(amount: float, rate: float) -> int:
	return int(ceil(maxf(0.0, amount / rate - 0.0000001)))
