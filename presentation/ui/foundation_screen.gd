extends Control

var panel: VBoxContainer
var lifecycle_panel: VBoxContainer
var inspector: Label

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
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(buttons)
	for item in [["+10m", 600], ["+1h", 3600], ["+8h", 28800], ["+1d", 86400], ["+7d", 604800]]:
		var button := Button.new()
		button.text = item[0]
		button.pressed.connect(func(): GameSession.advance_debug(item[1]); refresh())
		buttons.add_child(button)
	inspector = Label.new()
	inspector.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(inspector)
	refresh()

func _process(_delta: float) -> void:
	# Small presentation poll makes READY controls appear during normal foreground time.
	refresh_lifecycle_panel()

func refresh() -> void:
	refresh_lifecycle_panel()
	refresh_inspector()

func refresh_lifecycle_panel() -> void:
	for child in lifecycle_panel.get_children(): child.queue_free()
	var p: Dictionary = GameSession.profile
	var egg_value = p.get("active_egg", {})
	var egg: Dictionary = egg_value if egg_value is Dictionary else {}
	var state := String(egg.get("state", ""))
	if String(p.get("active_subject", "")) == "EGG":
		var status := Label.new()
		if state == "INCUBATING":
			status.text = "Egg\nStatus: Incubating\nRemaining: %s" % _remaining(int(egg.get("hatch_ready_at", 0)) - int(p.get("simulation", {}).get("last_simulated_at", 0)))
			lifecycle_panel.add_child(status)
			_add_button("Touch Egg", func(): GameSession.touch_egg(GameSession.clock.wall_utc()); refresh())
		elif state == "READY":
			status.text = "Egg\nStatus: Ready to hatch"
			lifecycle_panel.add_child(status)
			_add_button("Touch Egg", func(): GameSession.touch_egg(GameSession.clock.wall_utc()); refresh())
			_add_button("Hatch Egg", func(): _hatch())
		else:
			status.text = "Egg\nStatus: Hatching"
			lifecycle_panel.add_child(status)
			_add_button("Continue Hatching", func(): _hatch())
	elif String(p.get("active_subject", "")) == "PET":
		var pet_label := Label.new()
		pet_label.text = "Newborn Pet"
		lifecycle_panel.add_child(pet_label)

func refresh_inspector() -> void:
	var p: Dictionary = GameSession.profile
	var s: Dictionary = p.get("simulation", {})
	var pet_value = p.get("active_pet", {})
	var pet: Dictionary = pet_value if pet_value is Dictionary else {}
	var identity: Dictionary = pet.get("identity", {})
	var life: Dictionary = pet.get("life", {})
	var vitals: Dictionary = pet.get("vitals", {})
	inspector.text = "Active Subject: %s\nSchema Version: %s\nCurrent UTC: %s\nLast Simulated UTC: %s\nClock anomalies: %s\n\nPet ID: %s\nBorn At: %s\nLife state: %s\nGrowth stage: %s\nHunger: %s\nHydration: %s\nEnergy: %s\nHygiene: %s\nMood: %s\nHealth: %s" % [p.get("active_subject", "NONE"), p.get("schema_version", "?"), GameSession.clock.wall_utc(), s.get("last_simulated_at", "?"), s.get("clock_anomaly_count", 0), identity.get("pet_id", "No active pet"), identity.get("born_at", "n/a"), life.get("life_state", "n/a"), life.get("growth_stage", "n/a"), vitals.get("hunger", "n/a"), vitals.get("hydration", "n/a"), vitals.get("energy", "n/a"), vitals.get("hygiene", "n/a"), vitals.get("mood", "n/a"), vitals.get("health", "n/a")]

func _add_button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	lifecycle_panel.add_child(button)

func _remaining(seconds: int) -> String:
	return "%dh %dm" % [max(0, seconds) / 3600, (max(0, seconds) % 3600) / 60]

func _hatch() -> void:
	var now := GameSession.clock.wall_utc()
	var mono := GameSession.clock.monotonic_seconds()
	if String(GameSession.profile.get("active_egg", {}).get("state", "")) == "READY":
		if not GameSession.begin_hatching(now, mono): return
		refresh()
		await get_tree().create_timer(0.35).timeout
	GameSession.complete_hatching(GameSession.clock.wall_utc(), GameSession.clock.monotonic_seconds())
	refresh()
