class_name FoundationScreen
extends Control

const CompanionViewScript = preload("res://presentation/ui/companion_view.gd")

var panel: VBoxContainer
var lifecycle_panel: VBoxContainer
var inspector: Label
var lifecycle_status: Label
var lifecycle_remaining: Label
var rendered_lifecycle_signature := ""
var lifecycle_rebuild_count := 0
var session_override: PetGameSession
var reaction_label: Label
var language_input: LineEdit
var language_send: Button
var language_diagnostics: Label
var companion_view: CompanionView
var companion_header: Label
var needs_panel: VBoxContainer
var need_labels := {}
var language_panel: VBoxContainer
var developer_panel: VBoxContainer
var developer_toggle: Button
var developer_time_machine: HBoxContainer
var player_scroll: ScrollContainer
var developer_panel_visible := false
var button_style: StyleBoxFlat
var button_hover_style: StyleBoxFlat

func _session():
	return session_override if session_override != null else get_node_or_null("/root/GameSession")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_lightweight_theme()
	player_scroll = ScrollContainer.new()
	player_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	add_child(player_scroll)
	panel = VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 10)
	player_scroll.add_child(panel)
	companion_header = Label.new()
	companion_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	companion_header.add_theme_font_size_override("font_size", 22)
	panel.add_child(companion_header)
	lifecycle_status = Label.new()
	lifecycle_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lifecycle_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(lifecycle_status)
	companion_view = CompanionViewScript.new()
	companion_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(companion_view)
	needs_panel = VBoxContainer.new()
	needs_panel.add_theme_constant_override("separation", 3)
	panel.add_child(needs_panel)
	lifecycle_panel = VBoxContainer.new()
	lifecycle_panel.add_theme_constant_override("separation", 6)
	panel.add_child(lifecycle_panel)
	reaction_label = Label.new()
	reaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reaction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(reaction_label)
	language_panel = VBoxContainer.new()
	panel.add_child(language_panel)
	language_input = LineEdit.new()
	language_input.placeholder_text = "Say something in English"
	language_input.custom_minimum_size = Vector2(0, 44)
	language_panel.add_child(language_input)
	language_send = Button.new()
	language_send.text = "Send"
	language_send.custom_minimum_size = Vector2(0, 44)
	_style_button(language_send)
	language_send.pressed.connect(func(): _speak())
	language_panel.add_child(language_send)
	developer_toggle = Button.new()
	developer_toggle.text = "Developer Tools"
	developer_toggle.custom_minimum_size = Vector2(0, 44)
	_style_button(developer_toggle)
	developer_toggle.pressed.connect(func(): set_developer_panel_visible(not developer_panel_visible))
	panel.add_child(developer_toggle)
	developer_panel = VBoxContainer.new()
	developer_panel.add_theme_constant_override("separation", 6)
	panel.add_child(developer_panel)
	var developer_title := Label.new()
	developer_title.text = "Developer diagnostics"
	developer_panel.add_child(developer_title)
	developer_time_machine = HBoxContainer.new()
	developer_time_machine.alignment = BoxContainer.ALIGNMENT_CENTER
	developer_panel.add_child(developer_time_machine)
	for item in [["+10m", 600], ["+1h", 3600], ["+8h", 28800], ["+1d", 86400], ["+7d", 604800]]:
		var button := Button.new()
		button.text = item[0]
		button.custom_minimum_size = Vector2(52, 44)
		_style_button(button)
		button.pressed.connect(func(): _session().advance_debug(item[1]); refresh())
		developer_time_machine.add_child(button)
	inspector = Label.new()
	inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	developer_panel.add_child(inspector)
	language_diagnostics = Label.new()
	language_diagnostics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	developer_panel.add_child(language_diagnostics)
	set_developer_panel_visible(false)
	refresh()

func _process(_delta: float) -> void:
	refresh()

func set_developer_panel_visible(value: bool) -> void:
	developer_panel_visible = value
	if developer_panel != null: developer_panel.visible = value
	if developer_toggle != null: developer_toggle.text = "Hide Developer Tools" if value else "Developer Tools"
	if language_diagnostics != null and _session() != null:
		language_diagnostics.visible = value and lifecycle_signature(_session().profile) in ["PET:ALIVE:STABLE:AWAKE", "PET:ALIVE:CRITICAL:AWAKE"]

func refresh() -> void:
	var session = _session()
	if session == null or session.profile.is_empty(): return
	refresh_lifecycle_panel()
	refresh_companion()
	refresh_needs()
	refresh_inspector()
	var available := lifecycle_signature(session.profile) in ["PET:ALIVE:STABLE:AWAKE", "PET:ALIVE:CRITICAL:AWAKE"]
	language_panel.visible = available
	language_input.visible = available
	language_send.visible = available
	# Diagnostics are developer-only even though their node remains available to tests.
	language_diagnostics.visible = developer_panel_visible and available

func lifecycle_signature(profile: Dictionary) -> String:
	var subject := String(profile.get("active_subject", "NONE"))
	if subject == "EGG": return "EGG:%s" % String(profile.get("active_egg", {}).get("state", "INVALID"))
	if subject == "PET":
		var pet: Dictionary = profile.get("active_pet", {})
		return "PET:%s:%s:%s" % [String(pet.get("life", {}).get("life_state", "UNKNOWN")), String(pet.get("survival", {}).get("condition", "STABLE")), String(pet.get("activity", {}).get("state", "AWAKE"))]
	if int(profile.get("memorial_count", 0)) <= 0: return "NONE"
	return "MEMORIAL:SNAPSHOT:%d" % int(profile.get("memorial_count", 0)) if not profile.get("memorials", []).is_empty() else "MEMORIAL:HISTORICAL_ONLY:%d" % int(profile.get("memorial_count", 0))

func refresh_lifecycle_panel() -> void:
	var signature := lifecycle_signature(_session().profile)
	if signature != rendered_lifecycle_signature:
		_rebuild_lifecycle_panel(signature)
		rendered_lifecycle_signature = signature
	_update_lifecycle_dynamic_text()

func _rebuild_lifecycle_panel(signature: String) -> void:
	# A lifecycle change can occur inside an action Button callback (for example
	# Sleep). Defer node disposal so Godot never frees the currently-emitting node.
	for child in lifecycle_panel.get_children():
		child.visible = false
		child.queue_free()
	lifecycle_rebuild_count += 1
	lifecycle_remaining = null
	if signature == "EGG:INCUBATING":
		lifecycle_remaining = Label.new()
		lifecycle_remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lifecycle_panel.add_child(lifecycle_remaining)
		_add_button("Touch Egg", func(): _session().touch_egg(_session().clock.wall_utc()); refresh())
	elif signature == "EGG:READY":
		_add_button("Touch Egg", func(): _session().touch_egg(_session().clock.wall_utc()); refresh())
		_add_button("Hatch Egg", func(): _hatch())
	elif signature == "EGG:HATCHING":
		_add_button("Continue Hatching", func(): _hatch())
	elif signature.begins_with("PET:DEAD:"):
		_add_button("Memorialize Pet", func(): _memorialize())
	elif signature in ["PET:ALIVE:STABLE:AWAKE", "PET:ALIVE:CRITICAL:AWAKE"]:
		for item in [["Feed", "feed"], ["Drink", "drink"], ["Play", "play"], ["Wash", "wash"], ["Touch", "touch"], ["Sleep", "sleep"]]: _add_button(item[0], func(): _care(item[1]))
	elif signature in ["PET:ALIVE:STABLE:SLEEPING", "PET:ALIVE:CRITICAL:SLEEPING"]:
		_add_button("Wake", func(): _care("wake"))
	elif signature.begins_with("MEMORIAL:SNAPSHOT:"):
		_add_button("New Egg", func(): _new_egg())

func _update_lifecycle_dynamic_text() -> void:
	var p: Dictionary = _session().profile
	var signature := lifecycle_signature(p)
	if signature == "EGG:INCUBATING":
		companion_header.text = "Egg"
		lifecycle_status.text = "Incubating"
		var remaining := int(p.get("active_egg", {}).get("hatch_ready_at", 0)) - int(p.get("simulation", {}).get("last_simulated_at", 0))
		lifecycle_remaining.text = "Ready in %s" % _remaining(remaining)
	elif signature == "EGG:READY":
		companion_header.text = "Egg"
		lifecycle_status.text = "Ready to hatch"
	elif signature == "EGG:HATCHING":
		companion_header.text = "Egg"
		lifecycle_status.text = "Hatching"
	elif signature.begins_with("PET:DEAD:"):
		var dead_pet: Dictionary = p.get("active_pet", {})
		companion_header.text = "%s — %s" % [String(dead_pet.get("identity", {}).get("name", "Pet")), String(dead_pet.get("life", {}).get("growth_stage", "NEWBORN")).capitalize()]
		lifecycle_status.text = "Permanent death\nCause: %s" % _readable_cause(String(dead_pet.get("life", {}).get("death_cause", "Unknown")))
	elif signature == "PET:ALIVE:CRITICAL:SLEEPING":
		companion_header.text = _pet_header(p)
		lifecycle_status.text = "Pet is sleeping\nCRITICAL — care is needed"
	elif signature == "PET:ALIVE:STABLE:SLEEPING":
		companion_header.text = _pet_header(p)
		lifecycle_status.text = "Pet is sleeping"
	elif signature.begins_with("PET:ALIVE:"):
		companion_header.text = _pet_header(p)
		var stage := String(p.get("active_pet", {}).get("life", {}).get("growth_stage", "NEWBORN")).capitalize()
		lifecycle_status.text = "%s Pet\nCRITICAL — care is needed" % stage if signature.contains(":CRITICAL:") else "%s Pet\nAwake and ready" % stage
	elif signature.begins_with("MEMORIAL:SNAPSHOT:"):
		var snapshot: Dictionary = p.get("memorials", [])[-1].get("pet_snapshot", {})
		companion_header.text = "%s Memorial" % String(snapshot.get("identity", {}).get("name", "Pet"))
		lifecycle_status.text = "%s\nBorn: %s\nDied: %s\nCause: %s" % [String(snapshot.get("life", {}).get("growth_stage", "NEWBORN")).capitalize(), _format_timestamp(snapshot.get("identity", {}).get("born_at")), _format_timestamp(snapshot.get("life", {}).get("died_at")), _readable_cause(String(snapshot.get("life", {}).get("death_cause", "Unknown")))]
	elif signature.begins_with("MEMORIAL:HISTORICAL_ONLY:"):
		companion_header.text = "Memorial"
		lifecycle_status.text = "Historical memorials: %s" % p.get("memorial_count", 0)
	else:
		companion_header.text = "Pet Game"
		lifecycle_status.text = "No active companion"

func refresh_companion() -> void:
	var profile: Dictionary = _session().profile
	var signature := lifecycle_signature(profile)
	var state := "NONE"
	var critical := false
	if signature.begins_with("EGG:"): state = "EGG"
	elif signature.begins_with("MEMORIAL:"): state = "MEMORIAL"
	elif signature.begins_with("PET:"):
		var pet: Dictionary = profile.get("active_pet", {})
		if signature.begins_with("PET:DEAD:"): state = "DEAD"
		elif String(pet.get("activity", {}).get("state", "AWAKE")) == "SLEEPING": state = "SLEEPING"
		else: state = String(pet.get("life", {}).get("growth_stage", "NEWBORN"))
		critical = String(pet.get("survival", {}).get("condition", "STABLE")) == "CRITICAL"
	companion_view.present(state, critical)

func refresh_needs() -> void:
	var pet_value = _session().profile.get("active_pet")
	var is_alive := pet_value is Dictionary and String(pet_value.get("life", {}).get("life_state", "")) == "ALIVE"
	needs_panel.visible = is_alive
	if not is_alive: return
	var vitals: Dictionary = pet_value.get("vitals", {})
	for key in ["hunger", "hydration", "energy", "hygiene", "mood", "health"]:
		if not need_labels.has(key):
			var label := Label.new()
			need_labels[key] = label
			needs_panel.add_child(label)
		need_labels[key].text = "%s: %d / 100" % [key.capitalize(), int(round(float(vitals.get(key, 0.0))))]

func has_lifecycle_button(text: String) -> bool:
	return lifecycle_button(text) != null

func lifecycle_button(text: String) -> Button:
	for child in lifecycle_panel.get_children():
		if child is Button and child.visible and child.text == text: return child
	return null

func has_need_label(key: String) -> bool:
	return need_labels.has(key) and is_instance_valid(need_labels[key]) and need_labels[key].visible

func refresh_inspector() -> void:
	var p: Dictionary = _session().profile
	var s: Dictionary = p.get("simulation", {})
	var pet_value = p.get("active_pet", {})
	var pet: Dictionary = pet_value if pet_value is Dictionary else {}
	var identity: Dictionary = pet.get("identity", {})
	var life: Dictionary = pet.get("life", {})
	var growth: Dictionary = pet.get("growth", {})
	var vitals: Dictionary = pet.get("vitals", {})
	var relationship: Dictionary = pet.get("relationship", {})
	var memory: Dictionary = pet.get("memory", {})
	var memory_events: Array = memory.get("events", [])
	var last_memory := "n/a"
	if not memory_events.is_empty():
		var last_record: Dictionary = memory_events[-1]
		last_memory = "%s @ %s" % [last_record.get("event_type", "n/a"), last_record.get("occurred_at", "n/a")]
	var relationship_text := "\n\nBond: %s\nTrust: %s\nCare Experience: %s\nMemory Events: %s\nFavorite Interaction: %s\nLast Memory: %s" % [relationship.get("bond", "n/a"), relationship.get("trust", "n/a"), relationship.get("care_experience", "n/a"), memory_events.size(), memory.get("semantic", {}).get("favorite_interaction", "n/a"), last_memory]
	var memorial_text := ""
	if String(p.get("active_subject", "NONE")) == "NONE" and int(p.get("memorial_count", 0)) > 0:
		var memorials: Array = p.get("memorials", [])
		if not memorials.is_empty():
			var snapshot: Dictionary = memorials[-1].get("pet_snapshot", {})
			var snapshot_identity: Dictionary = snapshot.get("identity", {})
			var snapshot_life: Dictionary = snapshot.get("life", {})
			memorial_text = "\n\nMemorial\nName: %s\nBorn At: %s\nDied At: %s\nDeath Cause: %s" % [snapshot_identity.get("name", "n/a"), snapshot_identity.get("born_at", "n/a"), snapshot_life.get("died_at", "n/a"), snapshot_life.get("death_cause", "n/a")]
		else:
			memorial_text = "\n\nMemorial\nHistorical memorials: %s" % p.get("memorial_count", 0)
	var recent := "\n\nRecent domain events:"
	for event in p.get("recent_events", []): recent += "\n• %s @ %s" % [event.get("event_type"), event.get("occurred_at")]
	inspector.text = "Active Subject: %s\nSchema Version: %s\nCurrent UTC: %s\nLast Simulated UTC: %s\nClock anomalies: %s\n\nPet ID: %s\nName: %s\nBorn At: %s\nLife state: %s\nGrowth stage: %s\nStage Started At: %s\nDied At: %s\nDeath Cause: %s\nHunger: %s\nHydration: %s\nEnergy: %s\nHygiene: %s\nMood: %s\nHealth: %s%s%s%s" % [p.get("active_subject", "NONE"), p.get("schema_version", "?"), _session().clock.wall_utc(), s.get("last_simulated_at", "?"), s.get("clock_anomaly_count", 0), identity.get("pet_id", "No active pet"), identity.get("name", "n/a"), identity.get("born_at", "n/a"), life.get("life_state", "n/a"), life.get("growth_stage", "n/a"), growth.get("stage_started_at", "n/a"), life.get("died_at", "n/a"), life.get("death_cause", "n/a"), vitals.get("hunger", "n/a"), vitals.get("hydration", "n/a"), vitals.get("energy", "n/a"), vitals.get("hygiene", "n/a"), vitals.get("mood", "n/a"), vitals.get("health", "n/a"), relationship_text, memorial_text, recent]

func _add_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 44)
	_style_button(button)
	button.pressed.connect(callback)
	lifecycle_panel.add_child(button)

func _apply_lightweight_theme() -> void:
	button_style = StyleBoxFlat.new()
	button_style.bg_color = Color("39516b")
	button_style.border_color = Color("91b8d6")
	button_style.set_border_width_all(1)
	button_style.corner_radius_top_left = 6
	button_style.corner_radius_top_right = 6
	button_style.corner_radius_bottom_left = 6
	button_style.corner_radius_bottom_right = 6
	button_hover_style = button_style.duplicate()
	button_hover_style.bg_color = Color("527895")
	add_theme_color_override("font_color", Color("edf4ff"))

func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", button_style)
	button.add_theme_stylebox_override("hover", button_hover_style)
	button.add_theme_color_override("font_color", Color("f5f9ff"))

func _remaining(seconds: int) -> String:
	return "%dh %dm" % [max(0, seconds) / 3600, (max(0, seconds) % 3600) / 60]

func _pet_header(profile: Dictionary) -> String:
	var pet: Dictionary = profile.get("active_pet", {})
	return "%s — %s" % [String(pet.get("identity", {}).get("name", "Pet")), String(pet.get("life", {}).get("growth_stage", "NEWBORN")).capitalize()]

func _readable_cause(cause: String) -> String:
	return cause.replace("_", " ").capitalize()

func _format_timestamp(at: Variant) -> String:
	if not (at is int) or int(at) < 0: return "Unknown"
	var utc := Time.get_datetime_dict_from_unix_time(int(at))
	if not (utc is Dictionary): return "Unknown"
	return "%04d-%02d-%02d %02d:%02d UTC" % [int(utc.get("year", 0)), int(utc.get("month", 0)), int(utc.get("day", 0)), int(utc.get("hour", 0)), int(utc.get("minute", 0))]

func _hatch() -> void:
	var now: int = _session().clock.wall_utc()
	var mono: float = _session().clock.monotonic_seconds()
	if String(_session().profile.get("active_egg", {}).get("state", "")) == "READY":
		if not _session().begin_hatching(now, mono): return
		refresh()
		await get_tree().create_timer(0.35).timeout
	_session().complete_hatching(_session().clock.wall_utc(), _session().clock.monotonic_seconds())
	refresh()

func _care(action: String) -> void:
	var result: Dictionary = _session().care_action(action, _session().clock.monotonic_seconds())
	if result.ok:
		reaction_label.text = {"feed":"Fed — pet ate happily.", "drink":"Drank — pet drank.", "play":"Played — pet had fun.", "wash":"Clean — pet is clean.", "touch":"Reaction: HAPPY", "sleep":"Sleeping", "wake":"Awake"}.get(action, "Ready")
	else:
		reaction_label.text = {"LOW_ENERGY":"Too tired to play", "PET_SLEEPING":"Pet is sleeping", "NOT_SLEEPING":"Pet is already awake", "NO_PET":"No pet is available", "PET_DEAD":"A dead pet cannot be cared for", "PERSIST_FAILED":"Action could not be saved", "UNKNOWN_ACTION":"That action is unavailable"}.get(String(result.reason), "Action unavailable")
	refresh()

func _memorialize() -> void:
	var result: Dictionary = _session().memorialize_pet(_session().clock.monotonic_seconds())
	reaction_label.text = "Memorialized" if result.ok else "Memorial could not be saved"
	refresh()

func _new_egg() -> void:
	var result: Dictionary = _session().request_new_egg(_session().clock.monotonic_seconds())
	reaction_label.text = "A new egg arrived" if result.ok else "A new egg could not be saved"
	refresh()

func _speak() -> void:
	var result: Dictionary = _session().speak_to_pet(language_input.text, _session().clock.monotonic_seconds())
	if result.ok:
		reaction_label.text = "Reaction: %s" % String(result.reaction)
		language_diagnostics.text = "Intent: %s\nTopics: %s\nRule: %s\nMemory cue: %s" % [result.intent, ", ".join(result.topics), result.matched_rule_id, result.memory_cue]
		language_input.text = ""
	else:
		reaction_label.text = "Message rejected: %s" % result.reason
		language_diagnostics.text = "Message rejected: %s" % result.reason
	refresh()
