extends Control

var inspector: Label

func _ready() -> void:
	var panel := VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
	panel.add_theme_constant_override("separation", 8)
	add_child(panel)
	var title := Label.new()
	title.text = "PET PROJECT FOUNDATION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	var action := Button.new()
	var subject := String(GameSession.profile.get("active_subject", "NONE"))
	var egg_value = GameSession.profile.get("active_egg", {})
	var egg: Dictionary = egg_value if egg_value is Dictionary else {}
	if subject == "EGG":
		if String(egg.get("state", "")) in ["INCUBATING", "READY"]:
			action.text = "Touch Egg"
			action.pressed.connect(func(): GameSession.touch_egg(GameSession.clock.wall_utc()); refresh())
			panel.add_child(action)
		if String(egg.get("state", "")) == "READY":
			var hatch := Button.new()
			hatch.text = "Hatch Egg"
			hatch.pressed.connect(func(): _hatch())
			panel.add_child(hatch)
		elif String(egg.get("state", "")) == "HATCHING":
			action.text = "Continue Hatching"
			action.pressed.connect(func(): _hatch())
			panel.add_child(action)
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

func refresh() -> void:
	var p: Dictionary = GameSession.profile
	var s: Dictionary = p.get("simulation", {})
	var pet_value = p.get("active_pet", {})
	var pet: Dictionary = pet_value if pet_value is Dictionary else {}
	var identity: Dictionary = pet.get("identity", {})
	var life: Dictionary = pet.get("life", {})
	var vitals: Dictionary = pet.get("vitals", {})
	var text := "Active Subject: %s\nSchema Version: %s\nSimulation Version: %s\nBalance Version: %s\n\nCurrent UTC: %s\nLast Simulated UTC: %s\nClock anomalies: %s\n\n" % [p.get("active_subject", "NONE"), p.get("schema_version", "?"), s.get("simulation_version", "?"), s.get("balance_version", "?"), GameSession.clock.wall_utc(), s.get("last_simulated_at", "?"), s.get("clock_anomaly_count", 0)]
	text += "Pet ID: %s\nLife state: %s\nGrowth stage: %s\nHunger: %s\nHydration: %s\nEnergy: %s\nHygiene: %s\nMood: %s\nHealth: %s\n\nRecent domain events:\n" % [identity.get("pet_id", "No active pet"), life.get("life_state", "n/a"), life.get("growth_stage", "n/a"), vitals.get("hunger", "n/a"), vitals.get("hydration", "n/a"), vitals.get("energy", "n/a"), vitals.get("hygiene", "n/a"), vitals.get("mood", "n/a"), vitals.get("health", "n/a")]
	for event in p.get("recent_events", []): text += "• %s @ %s\n" % [event.get("event_type"), event.get("occurred_at")]
	inspector.text = text

func _hatch() -> void:
	var now := GameSession.clock.wall_utc()
	var mono := GameSession.clock.monotonic_seconds()
	if String(GameSession.profile.get("active_egg", {}).get("state", "")) == "READY":
		GameSession.begin_hatching(now, mono)
		refresh()
		await get_tree().create_timer(0.35).timeout
	GameSession.complete_hatching(GameSession.clock.wall_utc(), GameSession.clock.monotonic_seconds())
	refresh()
