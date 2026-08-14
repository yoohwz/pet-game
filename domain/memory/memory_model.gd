class_name MemoryModel
extends RefCounted

const ROUTINE_ACTIONS := ["feed", "drink", "play", "wash", "touch", "sleep", "wake"]
const CARE_ACTIONS := ["feed", "drink", "play", "wash", "touch"]
const MAPPING := {"pet_hatched":{"category":"LIFECYCLE","importance":4,"valence":1}, "pet_grew":{"category":"LIFECYCLE","importance":4,"valence":1}, "pet_fed":{"category":"CARE","importance":1}, "pet_drank":{"category":"CARE","importance":1}, "pet_washed":{"category":"CARE","importance":1}, "pet_touched":{"category":"CARE","importance":1,"valence":1}, "pet_played":{"category":"CARE","importance":1,"valence":1}, "pet_sleep_started":{"category":"ROUTINE","importance":0,"valence":0}, "pet_woke":{"category":"ROUTINE","importance":0,"valence":0}, "pet_became_critical":{"category":"SURVIVAL","importance":3,"valence":-1}, "pet_stabilized":{"category":"SURVIVAL","importance":3,"valence":1}, "pet_died":{"category":"SURVIVAL","importance":4,"valence":-1}}

static func new_memory() -> Dictionary:
	var routine := {}
	for action in ROUTINE_ACTIONS: routine[action] = {"count":0, "meaningful_count":0, "last_at":null}
	return {"memory_version":1, "next_sequence":0, "events":[], "routine":routine, "semantic":{"care_interaction_count":0, "rescue_count":0, "critical_count":0, "favorite_interaction":null}}

static func project(memory: Dictionary, event: Dictionary, config: Dictionary) -> Dictionary:
	var next: Dictionary = memory.duplicate(true)
	var event_type := String(event.get("event_type", ""))
	if not MAPPING.has(event_type): return next
	var source_id := String(event.get("event_id", ""))
	if source_id.is_empty(): return next
	for old in next.get("events", []):
		if String(old.get("source_event_id", "")) == source_id: return next
	var mapping: Dictionary = MAPPING[event_type]
	var details: Dictionary = event.get("payload", {}).duplicate(true)
	var action := String(details.get("action", _action_for_event(event_type)))
	if not action.is_empty(): details["action"] = action
	var meaningful := bool(details.get("meaningful", event_type in ["pet_touched", "pet_played"]))
	var valence := int(mapping.get("valence", 1 if meaningful else 0))
	var record := {"schema_version":1, "memory_id":"memory:%s" % source_id, "source_event_id":source_id, "sequence":int(next.next_sequence), "event_type":event_type, "occurred_at":int(event.get("occurred_at", 0)), "category":mapping.category, "valence":valence, "importance":int(mapping.importance), "details":details}
	next.events.append(record); next.next_sequence = int(next.next_sequence) + 1
	_update_projections(next, action, meaningful, event_type, int(record.occurred_at))
	_evict(next, int(config.get("event_store_limit", 64)))
	return next

static func working_memory(memory: Dictionary, config: Dictionary) -> Array:
	var events: Array = memory.get("events", []).duplicate(true)
	events.sort_custom(func(a, b): return int(a.sequence) < int(b.sequence))
	var limit := int(config.get("working_memory_limit", 8))
	return events.slice(max(0, events.size() - limit))

static func episodic_memory(memory: Dictionary, config: Dictionary) -> Array:
	return _filtered(memory, func(event): return int(event.importance) >= int(config.get("episodic_min_importance", 3)))

static func emotional_memory(memory: Dictionary) -> Array:
	return _filtered(memory, func(event): return int(event.valence) != 0)

static func _filtered(memory: Dictionary, predicate: Callable) -> Array:
	var output: Array = []
	for event in memory.get("events", []):
		if predicate.call(event): output.append(event.duplicate(true))
	output.sort_custom(func(a, b): return int(a.sequence) < int(b.sequence))
	return output

static func _update_projections(memory: Dictionary, action: String, meaningful: bool, event_type: String, at: int) -> void:
	var semantic: Dictionary = memory.semantic
	# Survival/lifecycle records may include a causal action for audit, but only
	# actual interaction events are routine occurrences.
	if event_type in ["pet_fed", "pet_drank", "pet_washed", "pet_touched", "pet_played", "pet_sleep_started", "pet_woke"] and action in ROUTINE_ACTIONS:
		var routine: Dictionary = memory.routine[action]
		routine.count = int(routine.count) + 1; routine.last_at = at
		if meaningful or action in ["sleep", "wake"]: routine.meaningful_count = int(routine.meaningful_count) + 1
		memory.routine[action] = routine
	if action in CARE_ACTIONS and meaningful:
		semantic.care_interaction_count = int(semantic.care_interaction_count) + 1
		var favorite = semantic.favorite_interaction
		if favorite == null or int(memory.routine[action].meaningful_count) > int(memory.routine[favorite].meaningful_count): semantic.favorite_interaction = action
	if event_type == "pet_stabilized": semantic.rescue_count = int(semantic.rescue_count) + 1
	if event_type == "pet_became_critical": semantic.critical_count = int(semantic.critical_count) + 1
	memory.semantic = semantic

static func _evict(memory: Dictionary, limit: int) -> void:
	while memory.events.size() > limit:
		var victim := 0
		for index in range(1, memory.events.size()):
			var current: Dictionary = memory.events[index]; var chosen: Dictionary = memory.events[victim]
			if int(current.importance) < int(chosen.importance) or (int(current.importance) == int(chosen.importance) and int(current.sequence) < int(chosen.sequence)): victim = index
		memory.events.remove_at(victim)

static func _action_for_event(event_type: String) -> String:
	return {"pet_fed":"feed", "pet_drank":"drink", "pet_washed":"wash", "pet_touched":"touch", "pet_played":"play", "pet_sleep_started":"sleep", "pet_woke":"wake"}.get(event_type, "")
