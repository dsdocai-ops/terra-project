class_name RopeVotePrompt
extends Control
## The extraction vote: an oval plaque asking "Climb the rope?", one dot per
## living player (green once they agreed, hollow while undecided) and the two
## answers. Owned by ui-hud (Dev B). Sync: presentation only; the answer is sent
## to the host, which tallies it (GameState.request_extract_vote).
## The host side of the tally is the week-5 run-economy deferral, so the HUD shows
## this prompt only when a `rope_vote_updated` broadcast arrives.

signal voted(yes: bool)

var agreed: int = 0:
	set(value):
		agreed = value
		queue_redraw()
var total: int = 0:
	set(value):
		total = value
		queue_redraw()
var selected_yes: bool = true:
	set(value):
		selected_yes = value
		queue_redraw()
var floor_text: String = ""


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Reads a rope_vote_updated payload: peer_id -> bool (true = yes). Anything
## else is ignored, so a malformed broadcast cannot raise the prompt.
func apply_votes(votes: Dictionary) -> void:
	var yes_count: int = 0
	for answer: Variant in votes.values():
		if answer is bool and answer:
			yes_count += 1
	agreed = yes_count
	total = votes.size()
	visible = total > 0
	if visible:
		grab_focus()


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right"):
		selected_yes = not selected_yes
		accept_event()
	elif event.is_action_pressed(&"ui_accept"):
		voted.emit(selected_yes)
		accept_event()


func _draw() -> void:
	var center := size * 0.5
	var rx: float = minf(size.x * 0.5, 170.0)
	var ry: float = rx * 0.5
	var ring := PackedVector2Array()
	for step: int in 41:
		var angle: float = TAU * float(step) / 40.0
		ring.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	UiPalette.fill_polygon(self, ring, UiPalette.STONE)
	UiPalette.outline_polygon(self, ring, UiPalette.BRONZE, 2)
	var font: Font = get_theme_default_font()
	UiPalette.draw_outlined(self, font, center + Vector2(-rx, -ry * 0.42), "Climb the rope?", 16, UiPalette.GOLD, HORIZONTAL_ALIGNMENT_CENTER, rx * 2.0)
	UiPalette.draw_outlined(self, font, center + Vector2(-rx, -ry * 0.12), "Everyone alive has to agree.", 8, UiPalette.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, rx * 2.0)
	var dot_gap: float = 22.0
	var start_x: float = center.x - dot_gap * float(total - 1) * 0.5
	for index: int in total:
		var at := Vector2(start_x + dot_gap * float(index), center.y + ry * 0.12)
		if index < agreed:
			UiPalette.fill_circle(self, at, 8.0, UiPalette.ALLY_GREEN)
		else:
			UiPalette.ring(self, at, 8.0, 2.0, UiPalette.DOWNED_GREY)
	var yes_color: Color = UiPalette.GOLD if selected_yes else UiPalette.PARCHMENT
	var no_color: Color = UiPalette.PARCHMENT if selected_yes else UiPalette.GOLD
	UiPalette.draw_outlined(self, font, center + Vector2(-rx * 0.5 - 60.0, ry * 0.6), ("> " if selected_yes else "  ") + "Climb", 16, yes_color, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	UiPalette.draw_outlined(self, font, center + Vector2(rx * 0.5 - 60.0, ry * 0.6), ("  " if selected_yes else "> ") + "Stay", 16, no_color, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
