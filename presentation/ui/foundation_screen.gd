class_name FoundationScreen
extends Control

var panel: VBoxContainer
var lifecycle_panel: VBoxContainer
var inspector: Label
var lifecycle_status: Label
var lifecycle_remaining: Label
var rendered_lifecycle_signature := ""
var lifecycle_rebuild_count := 0
var session_override: PetGameSession
var reaction_label: Label

func _session():
	return session_override if session_override != null else get_node_or_null("/root/GameSession")

func _ready() -> void:
	panel = VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
	panel.add_theme_constant_override("separation", 8)
	add_child(panel)
	var title := Label.new()
	title.text = "PET PROJECT FOUNDATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	lifecycle_panel = VBoxContainer.new()
	panel.add_child(lifecycle_panel)
	reaction_label = Label.new()
	reaction_label.text = ""
	panel.add_child(reaction_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(buttons)
	for item in [["+10m", 600], ["+1h", 3600], ["+8h", 28800], ["+1d", 86400], ["+7d", 604800]]:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(func(): _session().advance_debug(item[1]); refresh())
		buttons.add_child(button)
	inspector = Label.new()
	inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(inspector)
	refresh()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	refresh_lifecycle_panel()
	refresh_inspector()

func lifecycle_signature(profile: Dictionary) -> String:
	var subject := String(profile.get("active_subject", "NONE"))
	if subject == "EGG": return "EGG:%s" % String(profile.get("active_egg", {}).get("state", "INVALID"))
	if subject == "PET":
		var pet: Dictionary = profile.get("active_pet", {})
		return "PET:%s:%s:%s" % [String(pet.get("life", {}).get("life_state", "UNKNOWN")), String(pet.get("survival", {}).get("condition", "STABLE")), String(pet.get("activity", {}).get("state", "AWAKE"))]
	return "MEMORIAL:%d" % int(profile.get("memorial_count", 0)) if int(profile.get("memorial_count", 0)) > 0 else "NONE"

func refresh_lifecycle_panel() -> void:
	var signature := lifecycle_signature(_session().profile)
	if signature != rendered_lifecycle_signature:
		_rebuild_lifecycle_panel(signature)
		rendered_lifecycle_signature = signature
	_update_lifecycle_dynamic_text()

func _rebuild_lifecycle_panel(signature: String) -> void:
	for child in lifecycle_panel.get_children(): child.free()
	lifecycle_rebuild_count += 1
	lifecycle_status = Label.new()
	lifecycle_panel.add_child(lifecycle_status)
	lifecycle_remaining = null
	if signature == "EGG:INCUBATING":
		lifecycle_remaining = Label.new()
		lifecycle_panel.add_child(lifecycle_remaining)
		_add_button("Touch Egg", func(): _session().touch_egg(_session().clock.wall_utc()); refresh())
	elif signature == "EGG:READY":
		_add_button("Touch Egg", func(): _session().touch_egg(_session().clock.wall_utc()); refresh())
		_add_button("Hatch Egg", func(): _hatch())
	elif signature == "EGG:HATCHING":
		_add_button("Continue Hatching", func(): _hatch())
	elif signature.begins_with("PET:DEAD:"):
		_add_button("Memorialize Pet", func(): _memorialize())
	elif signature == "PET:ALIVE:STABLE:AWAKE" or signature == "PET:ALIVE:CRITICAL:AWAKE":
		for item in [["Feed", "feed"], ["Drink", "drink"], ["Play", "play"], ["Wash", "wash"], ["Touch", "touch"], ["Sleep", "sleep"]]: _add_button(item[0], func(): _care(item[1]))
	elif signature == "PET:ALIVE:STABLE:SLEEPING" or signature == "PET:ALIVE:CRITICAL:SLEEPING":
		_add_button("Wake", func(): _care("wake"))
	elif signature.begins_with("MEMORIAL:"):
		_add_button("New Egg", func(): _new_egg())

func _update_lifecycle_dynamic_text() -> void:
	var p: Dictionary = _session().profile
	var signature := lifecycle_signature(p)
	if signature == "EGG:INCUBATING":
		lifecycle_status.text = "Egg\nStatus: Incubating"
		var remaining := int(p.get("active_egg", {}).get("hatch_ready_at", 0)) - int(p.get("simulation", {}).get("last_simulated_at", 0))
		lifecycle_remaining.text = "Remaining: %s" % _remaining(remaining)
	elif signature == "EGG:READY": lifecycle_status.text = "Egg\nStatus: Ready to hatch"
	elif signature == "EGG:HATCHING": lifecycle_status.text = "Egg\nStatus: Hatching"
	elif signature.begins_with("PET:DEAD:"): lifecycle_status.text = "Pet has died\nMemorialize when you are ready"
	elif signature.ends_with(":SLEEPING"): lifecycle_status.text = "Pet is sleeping"
	elif signature.begins_with("PET:ALIVE:"):
		var condition := String(p.get("active_pet", {}).get("survival", {}).get("condition", "STABLE"))
		lifecycle_status.text = "Newborn Pet\nCRITICAL — care is needed" if condition == "CRITICAL" else "Newborn Pet"
	elif signature.begins_with("MEMORIAL:"): lifecycle_status.text = "Memorial\nA new egg is available when you are ready."
	else: lifecycle_status.text = "No active subject"

func has_lifecycle_button(text: String) -> bool:
	for child in lifecycle_panel.get_children():
		if child is Button and child.text == text: return true
	return false

func lifecycle_button(text: String) -> Button:
	for child in lifecycle_panel.get_children():
		if child is Button and child.text == text: return child
	return null

func refresh_inspector() -> void:
	var p: Dictionary = _session().profile
	var s: Dictionary = p.get("simulation", {})
	var pet_value = p.get("active_pet", {})
	var pet: Dictionary = pet_value if pet_value is Dictionary else {}
	var identity: Dictionary = pet.get("identity", {})
	var life: Dictionary = pet.get("life", {})
	var vitals: Dictionary = pet.get("vitals", {})
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
	inspector.text = "Active Subject: %s\nSchema Version: %s\nCurrent UTC: %s\nLast Simulated UTC: %s\nClock anomalies: %s\n\nPet ID: %s\nName: %s\nBorn At: %s\nLife state: %s\nGrowth stage: %s\nDied At: %s\nDeath Cause: %s\nHunger: %s\nHydration: %s\nEnergy: %s\nHygiene: %s\nMood: %s\nHealth: %s%s%s" % [p.get("active_subject", "NONE"), p.get("schema_version", "?"), _session().clock.wall_utc(), s.get("last_simulated_at", "?"), s.get("clock_anomaly_count", 0), identity.get("pet_id", "No active pet"), identity.get("name", "n/a"), identity.get("born_at", "n/a"), life.get("life_state", "n/a"), life.get("growth_stage", "n/a"), life.get("died_at", "n/a"), life.get("death_cause", "n/a"), vitals.get("hunger", "n/a"), vitals.get("hydration", "n/a"), vitals.get("energy", "n/a"), vitals.get("hygiene", "n/a"), vitals.get("mood", "n/a"), vitals.get("health", "n/a"), memorial_text, recent]

func _add_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	lifecycle_panel.add_child(button)

func _remaining(seconds: int) -> String:
	return "%dh %dm" % [max(0, seconds) / 3600, (max(0, seconds) % 3600) / 60]

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
		reaction_label.text = {"feed":"Pet ate happily.", "drink":"Pet drank.", "play":"Pet had fun.", "wash":"Pet is clean.", "touch":"Pet enjoyed the touch.", "sleep":"Pet fell asleep.", "wake":"Pet woke up."}.get(action, "Pet responded.")
	else:
		reaction_label.text = {"LOW_ENERGY":"Pet is too tired to play.", "PET_SLEEPING":"Pet is sleeping.", "NOT_SLEEPING":"Pet is already awake.", "NO_PET":"No pet is available.", "PET_DEAD":"A dead pet cannot be cared for.", "PERSIST_FAILED":"Action could not be saved.", "UNKNOWN_ACTION":"That action is unavailable."}.get(String(result.reason), "Action unavailable.")
	refresh()

func _memorialize() -> void:
	var result: Dictionary = _session().memorialize_pet(_session().clock.monotonic_seconds())
	reaction_label.text = "Pet memorialized." if result.ok else "Memorial could not be saved."
	refresh()

func _new_egg() -> void:
	var result: Dictionary = _session().request_new_egg(_session().clock.monotonic_seconds())
	reaction_label.text = "A new egg arrived." if result.ok else "A new egg could not be saved."
	refresh()
