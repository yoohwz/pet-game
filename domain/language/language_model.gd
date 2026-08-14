class_name LanguageModel
extends RefCounted

const INTENTS := ["GREETING","AFFECTION","PRAISE","PLAY_INVITE","FOOD_OFFER","GOODNIGHT","APOLOGY","USER_SAD","USER_HAPPY","QUESTION","OTHER"]
const TOPICS := ["FOOD","PLAY","SLEEP","PET","USER"]
const REACTIONS := ["ACKNOWLEDGE","AFFECTIONATE","HAPPY","EXCITED","EAGER","SLEEPY","FORGIVING","COMFORTING","CURIOUS","LISTENING"]
const CUES := ["NONE","RECOGNIZED_REPEAT","FAMILIAR_TOPIC"]

static func normalize(text: String) -> String:
	var output := text.strip_edges().to_lower()
	for punctuation in [".", ",", "!", "?", ";", ":", "(", ")", "[", "]", "\"", "'"]:
		output = output.replace(punctuation, " ")
	for whitespace in ["\t", "\n", "\r"]:
		output = output.replace(whitespace, " ")
	return " ".join(output.split(" ", false))

static func tokens(text: String) -> Array:
	return normalize(text).split(" ", false)

static func understand(text: String, memory: Dictionary, rules: Dictionary) -> Dictionary:
	var normalized := normalize(text)
	if normalized.is_empty(): return {"ok":false,"reason":"EMPTY_MESSAGE"}
	if text.length() > int(rules.get("max_input_chars", 256)): return {"ok":false,"reason":"MESSAGE_TOO_LONG"}
	var message_tokens: Array = tokens(normalized)
	var chosen: Dictionary = {}
	for rule_value in rules.get("intent_rules", []):
		var rule: Dictionary = rule_value
		for phrase_value in rule.get("phrases", []):
			if _contains_phrase(message_tokens, tokens(String(phrase_value))):
				if chosen.is_empty() or int(rule.get("priority", 0)) > int(chosen.get("priority", 0)) or (int(rule.get("priority", 0)) == int(chosen.get("priority", 0)) and String(rule.get("id", "")) < String(chosen.get("id", ""))): chosen = rule
	var intent := "OTHER"; var sentiment := 0; var reaction := "LISTENING"; var rule_id := ""
	if not chosen.is_empty(): intent = String(chosen.intent); sentiment = int(chosen.sentiment); reaction = String(chosen.reaction); rule_id = String(chosen.id)
	elif text.strip_edges().ends_with("?"):
		intent = "QUESTION"; sentiment = int(rules.get("fallbacks", {}).get("QUESTION", {}).get("sentiment", 0)); reaction = String(rules.get("fallbacks", {}).get("QUESTION", {}).get("reaction", "CURIOUS")); rule_id = "question-fallback"
	var topics: Array = []
	for topic in TOPICS:
		for token_value in rules.get("topics", {}).get(topic, []):
			if _contains_phrase(message_tokens, tokens(String(token_value))): topics.append(topic); break
	var cue := _memory_cue(normalized, topics, memory, rules)
	return {"ok":true,"language_version":1,"language_rules_version":int(rules.get("language_rules_version", 1)),"normalized_text":normalized,"intent":intent,"topics":topics,"sentiment":sentiment,"reaction":reaction,"memory_cue":cue,"matched_rule_id":rule_id}

static func _contains_phrase(message_tokens: Array, phrase_tokens: Array) -> bool:
	if phrase_tokens.is_empty() or phrase_tokens.size() > message_tokens.size(): return false
	for start in range(message_tokens.size() - phrase_tokens.size() + 1):
		var matched := true
		for offset in range(phrase_tokens.size()):
			if String(message_tokens[start + offset]) != String(phrase_tokens[offset]): matched = false; break
		if matched: return true
	return false

static func language_memories(memory: Dictionary) -> Array:
	var output: Array = []
	for event in memory.get("events", []):
		if String(event.get("event_type", "")) == "pet_heard_message": output.append(event.duplicate(true))
	output.sort_custom(func(a, b): return int(a.sequence) < int(b.sequence))
	return output

static func _memory_cue(normalized: String, topics: Array, memory: Dictionary, rules: Dictionary) -> String:
	var retained := language_memories(memory)
	var start: int = max(0, retained.size() - int(rules.get("repeat_window_messages", 8)))
	for index in range(start, retained.size()):
		if String(retained[index].get("details", {}).get("normalized_text", "")) == normalized: return "RECOGNIZED_REPEAT"
	var counts: Dictionary = memory.get("semantic", {}).get("language", {}).get("topic_counts", {})
	for topic in topics:
		if int(counts.get(topic, 0)) >= int(rules.get("familiar_topic_threshold", 3)): return "FAMILIAR_TOPIC"
	return "NONE"
