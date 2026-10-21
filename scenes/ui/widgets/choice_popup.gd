class_name ChoicePopup
extends Control
## The pick-one-of-three screen: up to three arched stone tablets, each with a
## carved icon in its rarity colour, a name, a description and its tags. Left and
## Right (or the mouse) move the highlight, Accept (or a click) takes the card.
## Owned by ui-hud (Dev B). Sync: presentation only. The pick is a request: the
## HUD sends it to the host, which validates and applies it (RelicFlow).

signal picked(index: int)

## Seconds after opening before input counts, so the press that opened the
## screen cannot also choose a card.
const ARM_SECONDS: float = 0.3

var options: Array[ChoiceOption] = []
var selected: int = 1:
	set(value):
		selected = value
		queue_redraw()
var title_text: String = "SHRINE OF ECHOES"
var waiting_text: String = ""

var _armed_at_msec: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	visible = false


func open(new_options: Array[ChoiceOption]) -> void:
	options = new_options
	selected = clampi(1, 0, maxi(options.size() - 1, 0))
	_armed_at_msec = Time.get_ticks_msec()
	visible = not options.is_empty()
	if visible:
		grab_focus()
	queue_redraw()


func close() -> void:
	options = []
	visible = false


func is_armed() -> bool:
	return Time.get_ticks_msec() - _armed_at_msec >= int(ARM_SECONDS * 1000.0)


func move_selection(step: int) -> void:
	if options.is_empty():
		return
	selected = posmod(selected + step, options.size())


## Takes the highlighted card. False while unarmed, empty, or when the card
## cannot be taken.
func choose(index: int) -> bool:
	if not is_armed() or index < 0 or index >= options.size():
		return false
	if options[index].disabled_reason != "":
		return false
	picked.emit(index)
	return true


## Size of one tablet at the current control size.
func tablet_size() -> Vector2:
	var width: float = minf(size.x * 0.2, 190.0)
	return Vector2(width, width * 1.4)


## The unrotated rectangle of card `index`, centred as a row on the screen.
func tablet_rect(index: int) -> Rect2:
	var card: Vector2 = tablet_size()
	var gap: float = card.x * 0.14
	var total: float = card.x * options.size() + gap * maxf(options.size() - 1, 0)
	var left: float = (size.x - total) * 0.5
	var top: float = (size.y - card.y) * 0.5 + 8.0
	return Rect2(Vector2(left + (card.x + gap) * index, top), card)


## An arch-topped tablet outline centred on the origin.
static func tablet_polygon(width: float, height: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var half: float = width * 0.5
	var arch_y: float = -height * 0.5 + half
	points.append(Vector2(-half, height * 0.5))
	points.append(Vector2(-half, arch_y))
	for step: int in range(1, 12):
		var angle: float = PI + PI * float(step) / 12.0
		points.append(Vector2(cos(angle) * half, arch_y + sin(angle) * half))
	points.append(Vector2(half, arch_y))
	points.append(Vector2(half, height * 0.5))
	return points


func _gui_input(event: InputEvent) -> void:
	if options.is_empty():
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		for index: int in options.size():
			if tablet_rect(index).has_point(motion.position):
				selected = index
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			for index: int in options.size():
				if tablet_rect(index).has_point(click.position):
					selected = index
					choose(index)
	elif event.is_action_pressed(&"ui_left"):
		move_selection(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_right"):
		move_selection(1)
		accept_event()
	elif event.is_action_pressed(&"ui_accept"):
		choose(selected)
		accept_event()


func _draw() -> void:
	if options.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.03, 0.02, 0.76))
	var font: Font = get_theme_default_font()
	UiPalette.draw_outlined(self, font, Vector2(0, tablet_rect(0).position.y - 18.0), title_text, 12, UiPalette.GOLD, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	for index: int in options.size():
		_draw_tablet(index, font)
	var hint: String = "Left / Right to look   Enter to take"
	if waiting_text != "":
		hint = waiting_text
	UiPalette.draw_outlined(self, font, Vector2(0, size.y - 14.0), hint, 8, UiPalette.ROPE, HORIZONTAL_ALIGNMENT_CENTER, size.x)


func _draw_tablet(index: int, font: Font) -> void:
	var option: ChoiceOption = options[index]
	var rect: Rect2 = tablet_rect(index)
	var is_selected: bool = index == selected
	var lift: float = -12.0 if is_selected else 0.0
	var center: Vector2 = rect.get_center() + Vector2(0, lift)
	var width: float = rect.size.x
	var height: float = rect.size.y
	var body: PackedVector2Array = UiPalette.placed(tablet_polygon(width, height), center)
	var rarity_color: Color = UiPalette.rarity_color(option.rarity)
	var blocked: bool = option.disabled_reason != ""
	if is_selected:
		UiPalette.fill_polygon(self, UiPalette.placed(tablet_polygon(width + 12.0, height + 12.0), center), Color(UiPalette.GOLD.r, UiPalette.GOLD.g, UiPalette.GOLD.b, 0.3))
	UiPalette.fill_polygon(self, UiPalette.placed(body, Vector2(3, 4)), Color(0, 0, 0, 0.45))
	UiPalette.fill_polygon(self, body, Color(0.91, 0.85, 0.69) if not blocked else Color(0.55, 0.5, 0.42))
	# A darker left edge and a lighter right edge give the slab some depth.
	UiPalette.line(self, body[0] + Vector2(4, -4), body[1] + Vector2(4, 4), Color(0.78, 0.7, 0.52), 2)
	UiPalette.outline_polygon(self, body, UiPalette.OUTLINE, 2)
	UiPalette.outline_polygon(self, UiPalette.placed(tablet_polygon(width - 8.0, height - 8.0), center), rarity_color if not blocked else UiPalette.DOWNED_GREY, 1)
	# Carved icon.
	var icon_center := center + Vector2(0, -height * 0.5 + width * 0.5)
	var icon_radius: float = width * 0.2
	UiPalette.fill_circle(self, icon_center, icon_radius * 1.35, UiPalette.OUTLINE)
	UiPalette.fill_circle(self, icon_center, icon_radius * 1.25, UiPalette.STONE_DARK)
	UiPalette.ring(self, icon_center, icon_radius * 1.25, 2.0, rarity_color)
	if option.icon != null:
		var icon_size: Vector2 = option.icon.get_size() * 3.0
		draw_texture_rect(option.icon, Rect2(icon_center - icon_size * 0.5, icon_size), false)
	else:
		UiPalette.fill_polygon(self, UiPalette.placed(RelicRope.charm_shape(option.rarity, icon_radius), icon_center), rarity_color)
	# Words. The tablet's ink is dark on parchment.
	var left: float = center.x - width * 0.5 + 12.0
	var inner: float = width - 24.0
	var cursor_y: float = icon_center.y + icon_radius * 1.35 + 22.0
	draw_string(font, Vector2(left, cursor_y), option.title, HORIZONTAL_ALIGNMENT_CENTER, inner, UiPalette.fit_size(font, option.title, inner), UiPalette.INK)
	cursor_y += 16.0
	draw_string(font, Vector2(left, cursor_y), UiPalette.rarity_name(option.rarity).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, inner, 8, rarity_color.darkened(0.45))
	cursor_y += 16.0
	draw_multiline_string(font, Vector2(left, cursor_y), option.description, HORIZONTAL_ALIGNMENT_CENTER, inner, 8, 6, UiPalette.INK)
	if blocked:
		draw_string(font, Vector2(left, center.y + height * 0.5 - 30.0), option.disabled_reason, HORIZONTAL_ALIGNMENT_CENTER, inner, 8, UiPalette.HP_RED)
	if not option.tags.is_empty():
		var tag_line: String = " / ".join(option.tags.map(func(tag: StringName) -> String: return String(tag).to_upper()))
		draw_string(font, Vector2(left, center.y + height * 0.5 - 14.0), tag_line, HORIZONTAL_ALIGNMENT_CENTER, inner, 8, UiPalette.STONE)
