class_name SaveMigrator
extends RefCounted

# Deliberate seam: Phase 0 only supports its initial schema.
static func migrate(data: Dictionary) -> Dictionary:
	if int(data.get("schema_version", 0)) != 1:
		return {}
	return data
