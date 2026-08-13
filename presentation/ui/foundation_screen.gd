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
	var text := "Active Subject: %s\nSchema Version: %s\n\nCurrent UTC: %s\nLast Simulated UTC: %s\nSimulation elapsed: %s\nClock anomalies: %s\n\n" % [p.get("active_subject", "NONE"), p.get("schema_version", "?"), GameSession.clock.wall_utc(), s.get("last_simulated_at", "?"), p.get("foundation_elapsed_seconds", 0), s.get("clock_anomaly_count", 0)]
	text += "Egg state: n/a\nPet ID: n/a\nLife state: n/a\nGrowth stage: n/a\nHunger / Hydration / Energy / Hygiene / Mood / Health: defaults reserved\nBond / Trust: defaults reserved\n\nRecent domain events:\n"
	for event in p.get("recent_events", []): text += "• %s @ %s\n" % [event.get("event_type"), event.get("occurred_at")]
	inspector.text = text
