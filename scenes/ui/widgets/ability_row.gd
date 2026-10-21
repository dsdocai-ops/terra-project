class_name AbilityRow
extends Control
## The bottom-centre cluster: three ability dials, the ultimate ring, the active
## relic dial and the potion flask, each with its key. Drawn on the UI pixel grid.
## Owned by ui-hud (Dev B). Sync: presentation only.
## blocked on Dev A (W5-A abilities): no ability data exists yet, so the three
## ability dials draw empty and dim; the ultimate ring, the active relic dial and
## the potion count are bound through the setters below the moment their owners
## publish the values.

const ACTIONS: Array[StringName] = [&"ability_1", &"ability_2", &"ability_3", &"ultimate", &"relic_active_1", &"potion"]

var ultimate_ratio: float = 0.0:
	set(value):
		ultimate_ratio = clampf(value, 0.0, 1.0)
		queue_redraw()
## 0 ready, 1 just used.
var relic_cooldown: float = 0.0:
	set(value):
		relic_cooldown = clampf(value, 0.0, 1.0)
		queue_redraw()
var has_active_relic: bool = false:
	set(value):
		has_active_relic = value
		queue_redraw()
var potion_count: int = 0:
	set(value):
		potion_count = value
		queue_redraw()


## The printed name of the key bound to `action`, "?" when nothing is bound.
static func key_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "?"
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var code: Key = key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
			return OS.get_keycode_string(code)
	return "pad"


func _draw() -> void:
	var font: Font = get_theme_default_font()
	var x: float = 4.0
	var base: float = size.y - 18.0
	# Three ability dials, stepped like an arc.
	for index: int in 3:
		var radius: float = 16.0
		var lift: float = 0.0 if index == 1 else 6.0
		var center := Vector2(x + radius, base - radius - lift)
		_dial(center, radius, UiPalette.BRONZE)
		UiPalette.draw_outlined(self, font, center + Vector2(-radius, 4.0), "-", 8, UiPalette.ROPE, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0)
		_key_tag(font, center + Vector2(0, radius + 12.0), ACTIONS[index])
		x += radius * 2.0 + 8.0
	# Ultimate ring.
	var ult_radius: float = 22.0
	var ult := Vector2(x + ult_radius, base - ult_radius)
	UiPalette.fill_circle(self, ult, ult_radius, UiPalette.OUTLINE)
	UiPalette.arc(self, ult, ult_radius - 4.0, 0.0, TAU, Color(0.1, 0.075, 0.05), 6.0)
	if ultimate_ratio > 0.0:
		UiPalette.arc(self, ult, ult_radius - 4.0, -PI * 0.5, -PI * 0.5 + TAU * ultimate_ratio, UiPalette.SHADOW_VIOLET, 6.0)
	UiPalette.fill_circle(self, ult, ult_radius - 8.0, UiPalette.STONE)
	UiPalette.draw_outlined(self, font, ult + Vector2(-ult_radius, 4.0), "%d%%" % int(round(ultimate_ratio * 100.0)), 8, UiPalette.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, ult_radius * 2.0)
	_key_tag(font, ult + Vector2(0, ult_radius + 12.0), ACTIONS[3])
	x += ult_radius * 2.0 + 8.0
	# Active relic dial.
	var relic_radius: float = 16.0
	var relic := Vector2(x + relic_radius, base - relic_radius - 6.0)
	_dial(relic, relic_radius, UiPalette.MANA_BLUE if has_active_relic else UiPalette.BRONZE)
	if has_active_relic and relic_cooldown > 0.0:
		UiPalette.arc(self, relic, relic_radius * 0.5, -PI * 0.5, -PI * 0.5 + TAU * relic_cooldown, Color(0, 0, 0, 0.75), relic_radius)
	_key_tag(font, relic + Vector2(0, relic_radius + 12.0), ACTIONS[4])
	x += relic_radius * 2.0 + 8.0
	# Potion flask.
	var flask: Texture2D = UiPalette.icon("potion_flask")
	var flask_at := Vector2(x, base - 40.0)
	if flask != null:
		self.draw_texture_rect(flask, Rect2(flask_at, flask.get_size() * 2.0), false, Color.WHITE if potion_count > 0 else Color(0.4, 0.4, 0.4))
	UiPalette.draw_outlined(self, font, flask_at + Vector2(0, 40.0), "x%d" % potion_count, 8, UiPalette.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, 32.0)
	_key_tag(font, flask_at + Vector2(16, 52.0), ACTIONS[5])


func _dial(center: Vector2, radius: float, rim: Color) -> void:
	UiPalette.fill_circle(self, center, radius + 2.0, UiPalette.OUTLINE)
	UiPalette.fill_circle(self, center, radius, rim)
	UiPalette.fill_circle(self, center, radius - 2.0, Color(0.1, 0.075, 0.05))


func _key_tag(font: Font, at: Vector2, action: StringName) -> void:
	UiPalette.draw_outlined(self, font, at + Vector2(-16, 0), key_label(action), 8, UiPalette.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, 32.0)
