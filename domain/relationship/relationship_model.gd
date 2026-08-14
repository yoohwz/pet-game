class_name RelationshipModel
extends RefCounted

const REWARD_ACTIONS := ["feed", "drink", "wash", "touch", "play"]

static func new_relationship() -> Dictionary:
	var last := {}
	for action in REWARD_ACTIONS: last[action] = null
	return {"relationship_version":1, "relationship_balance_version":1, "bond":0.0, "trust":0.0, "care_experience":0.0, "last_rewarded_at":last}

static func normalize(value: Dictionary) -> Dictionary:
	var next := new_relationship()
	for key in ["bond", "trust", "care_experience", "relationship_version", "relationship_balance_version"]:
		if value.has(key): next[key] = value[key]
	var supplied: Dictionary = value.get("last_rewarded_at", {})
	for action in REWARD_ACTIONS:
		if supplied.has(action): next.last_rewarded_at[action] = supplied[action]
	return next

static func is_reward_eligible(relationship: Dictionary, action: String, at: int, config: Dictionary) -> bool:
	if action not in REWARD_ACTIONS: return false
	var previous = relationship.get("last_rewarded_at", {}).get(action)
	return previous == null or at - int(previous) >= int(config.get("reward_cooldown_seconds", 300))

static func apply_reward(relationship: Dictionary, action: String, at: int, config: Dictionary) -> Dictionary:
	var next := normalize(relationship)
	var deltas := {"bond":0.0, "trust":0.0, "care_experience":0.0, "rewarded":false}
	if not is_reward_eligible(next, action, at, config): return {"relationship":next, "deltas":deltas}
	var reward: Dictionary = config.get("rewards", {}).get(action, {})
	var before_bond := float(next.bond)
	var before_trust := float(next.trust)
	var before_experience := float(next.care_experience)
	next.bond = clampf(before_bond + float(reward.get("bond", 0.0)), 0.0, 100.0)
	next.trust = clampf(before_trust + float(reward.get("trust", 0.0)), 0.0, 100.0)
	next.care_experience = maxf(0.0, before_experience + float(reward.get("care_experience", 0.0)))
	deltas.bond = float(next.bond) - before_bond
	deltas.trust = float(next.trust) - before_trust
	deltas.care_experience = float(next.care_experience) - before_experience
	deltas.rewarded = true
	next.last_rewarded_at[action] = at
	next.relationship_balance_version = int(config.get("relationship_balance_version", 1))
	return {"relationship":next, "deltas":deltas}

static func apply_rescue_bonus(relationship: Dictionary, config: Dictionary) -> Dictionary:
	var next := normalize(relationship)
	var reward: Dictionary = config.get("rescue", {})
	var before_bond := float(next.bond)
	var before_trust := float(next.trust)
	var before_experience := float(next.care_experience)
	next.bond = clampf(before_bond + float(reward.get("bond", 0.0)), 0.0, 100.0)
	next.trust = clampf(before_trust + float(reward.get("trust", 0.0)), 0.0, 100.0)
	next.care_experience = maxf(0.0, before_experience + float(reward.get("care_experience", 0.0)))
	var deltas := {"bond":float(next.bond) - before_bond, "trust":float(next.trust) - before_trust, "care_experience":float(next.care_experience) - before_experience}
	next.relationship_balance_version = int(config.get("relationship_balance_version", 1))
	return {"relationship":next, "deltas":deltas}
