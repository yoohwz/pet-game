class_name GrowthModel
extends RefCounted

const DomainEventScript = preload("res://domain/simulation/domain_event.gd")
const STAGES := ["NEWBORN", "CHILD", "ADOLESCENT", "ADULT"]

static func transitions_to(pet: Dictionary, target_time: int, config: Dictionary, simulation_version: int) -> Dictionary:
	var next: Dictionary = pet.duplicate(true)
	var life: Dictionary = next.get("life", {}).duplicate(true)
	var growth: Dictionary = next.get("growth", {}).duplicate(true)
	var identity: Dictionary = next.get("identity", {})
	var born_at := int(identity.get("born_at", target_time))
	var current_stage := String(life.get("growth_stage", "NEWBORN"))
	var version := int(config.get("growth_balance_version", growth.get("growth_balance_version", 1)))
	var events: Array = []
	for transition in _transitions(born_at, config):
		if _stage_index(current_stage) >= _stage_index(String(transition.to_stage)): continue
		if int(transition.at) > target_time: break
		var from_stage := current_stage
		var to_stage := String(transition.to_stage)
		life["growth_stage"] = to_stage
		growth["stage_started_at"] = int(transition.at)
		growth["growth_balance_version"] = version
		current_stage = to_stage
		events.append(DomainEventScript.make("growth:v%d:g%d:%s:%s:%s:%d" % [simulation_version, version, String(identity.get("pet_id", "pet")), from_stage, to_stage, int(transition.at)], "pet_grew", int(transition.at), String(identity.get("pet_id", "pet")), {"from_stage":from_stage, "to_stage":to_stage, "stage_started_at":int(transition.at), "growth_balance_version":version}))
	next["life"] = life
	next["growth"] = growth
	return {"pet":next, "events":events}

static func _transitions(born_at: int, config: Dictionary) -> Array:
	return [{"to_stage":"CHILD", "at":born_at + int(config.get("child_age_seconds", 172800))}, {"to_stage":"ADOLESCENT", "at":born_at + int(config.get("adolescent_age_seconds", 604800))}, {"to_stage":"ADULT", "at":born_at + int(config.get("adult_age_seconds", 1814400))}]

static func _stage_index(stage: String) -> int:
	return STAGES.find(stage)
