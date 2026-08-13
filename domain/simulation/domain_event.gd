class_name DomainEvent
extends RefCounted

static func make(event_id: String, event_type: String, occurred_at: int, subject_id: String, payload: Dictionary = {}) -> Dictionary:
	# Durable identity is supplied explicitly. Domain never creates it from process-local state.
	assert(not event_id.is_empty(), "Domain events require an explicit event_id")
	if event_id.is_empty(): return {}
	return {"schema_version": 1, "event_id": event_id, "event_type": event_type, "occurred_at": occurred_at, "subject_id": subject_id, "payload": payload}

static func is_valid(event: Dictionary) -> bool:
	return int(event.get("schema_version", 0)) == 1 and not String(event.get("event_id", "")).is_empty() and not String(event.get("event_type", "")).is_empty() and event.has("occurred_at") and event.has("subject_id") and event.has("payload")
