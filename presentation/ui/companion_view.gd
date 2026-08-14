class_name CompanionView
extends Control

# Presentation-only deterministic placeholder. The authoritative profile remains
# the source of every state supplied through `present`.
var visual_state := "NONE"
var critical := false

func _init() -> void:
	custom_minimum_size = Vector2(180, 150)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func present(next_state: String, is_critical := false) -> void:
	if visual_state == next_state and critical == is_critical:
		return
	visual_state = next_state
	critical = is_critical
	queue_redraw()

func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	var center := bounds.get_center()
	draw_style_box(_panel_style(), bounds)
	match visual_state:
		"EGG":
			_draw_ellipse(center, Vector2(30, 42), Color("f4d6a5"))
			draw_arc(center + Vector2(0, 14), 19, 0.2, 2.94, 16, Color("7a4b35"), 3)
		"SLEEPING":
			_draw_pet(center, Color("8cb5c4"), true)
			draw_string(ThemeDB.fallback_font, center + Vector2(44, -28), "Zz", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("dfefff"))
		"DEAD":
			_draw_pet(center, Color("6f7480"), false)
			draw_line(center + Vector2(-24, -8), center + Vector2(-8, 8), Color("2c3038"), 3)
			draw_line(center + Vector2(-8, -8), center + Vector2(-24, 8), Color("2c3038"), 3)
			draw_line(center + Vector2(8, -8), center + Vector2(24, 8), Color("2c3038"), 3)
			draw_line(center + Vector2(24, -8), center + Vector2(8, 8), Color("2c3038"), 3)
		"MEMORIAL":
			draw_rect(Rect2(center - Vector2(43, 48), Vector2(86, 82)), Color("5c6472"), true)
			draw_rect(Rect2(center - Vector2(43, 48), Vector2(86, 82)), Color("c8d0dd"), false, 2)
			draw_string(ThemeDB.fallback_font, center + Vector2(-27, -7), "MEMORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("f2f5fa"))
		"NEWBORN", "CHILD", "ADOLESCENT", "ADULT":
			var palette := {"NEWBORN":Color("f1b27b"), "CHILD":Color("f5cc7a"), "ADOLESCENT":Color("a5d99b"), "ADULT":Color("87b8e8")}
			_draw_pet(center, palette.get(visual_state, Color.WHITE), false)
		_:
			draw_string(ThemeDB.fallback_font, center + Vector2(-20, 5), "...", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("b7c2d5"))
	if critical:
		draw_rect(Rect2(12, 12, 94, 26), Color("9e363d"), true)
		draw_string(ThemeDB.fallback_font, Vector2(20, 32), "CRITICAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(25):
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)

func _draw_pet(center: Vector2, color: Color, closed_eyes: bool) -> void:
	draw_circle(center + Vector2(0, 10), 37, color)
	draw_circle(center + Vector2(-24, -28), 15, color)
	draw_circle(center + Vector2(24, -28), 15, color)
	if closed_eyes:
		draw_line(center + Vector2(-19, 2), center + Vector2(-7, 2), Color("26313d"), 3)
		draw_line(center + Vector2(7, 2), center + Vector2(19, 2), Color("26313d"), 3)
	else:
		draw_circle(center + Vector2(-13, 0), 4, Color("26313d"))
		draw_circle(center + Vector2(13, 0), 4, Color("26313d"))
	draw_arc(center + Vector2(0, 12), 12, 0.2, 2.94, 12, Color("26313d"), 2)

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("26313d")
	style.border_color = Color("52657a")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style
