class_name PlaceholderMenu
extends Control
## The main menu: Play Solo, Host, and Join with an IP field, drawn as carved
## gold-and-parchment text on a gentle curve instead of boxed buttons.
## Owned by foundation (look: ui-hud, Dev B). Sync: none.
## Codex and Settings join the list in weeks 11 and 12.

signal solo_pressed()
signal host_pressed()
signal join_pressed(ip: String)

const PARCHMENT := Color(0.910, 0.847, 0.690)
const GOLD := Color(0.949, 0.757, 0.306)
const TITLE_SIZE: int = 40
const ITEM_SIZE: int = 16
## Left indent per row so the list bows out like the pit wall.
const INDENTS: Array[int] = [0, 10, 16, 18]

@onready var ip_field: LineEdit = %IpField
@onready var status_label: Label = %Status
@onready var solo_button: Button = %Solo
@onready var host_button: Button = %Host
@onready var join_button: Button = %Join


func _ready() -> void:
	solo_button.pressed.connect(func() -> void: solo_pressed.emit())
	host_button.pressed.connect(func() -> void: host_pressed.emit())
	join_button.pressed.connect(func() -> void: join_pressed.emit(ip_field.text.strip_edges()))
	_style()
	solo_button.grab_focus()


func set_status(text: String) -> void:
	status_label.text = text


func _style() -> void:
	var panel := $Center/Panel as PanelContainer
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var title := $Center/Panel/Rows/Title as Label
	title.text = "SINKHOLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size", TITLE_SIZE)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_shadow_color", Color(0.35, 0.24, 0.1))
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.rotation = deg_to_rad(-2.0)
	title.pivot_offset = Vector2(0, 20)
	var buttons: Array[Button] = [solo_button, host_button, join_button]
	for index: int in buttons.size():
		_carve(buttons[index], INDENTS[index + 1])
	status_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
	ip_field.flat = true
	ip_field.add_theme_color_override("font_color", PARCHMENT)
	ip_field.add_theme_font_size_override("font_size", 16)
	ip_field.add_theme_stylebox_override("normal", _underline())
	ip_field.add_theme_stylebox_override("focus", _underline(GOLD))


## Turns a Button into carved text: no box, left aligned, gold when highlighted.
func _carve(button: Button, indent: int) -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = float(indent) + 8.0
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, empty)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", ITEM_SIZE)
	button.add_theme_color_override("font_color", PARCHMENT)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_focus_color", GOLD)
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.focus_entered.connect(_on_focus.bind(button))
	button.focus_exited.connect(_on_unfocus.bind(button))
	button.mouse_entered.connect(button.grab_focus)


func _on_focus(button: Button) -> void:
	button.text = "> " + button.text.trim_prefix("> ")


func _on_unfocus(button: Button) -> void:
	button.text = button.text.trim_prefix("> ")


func _underline(color: Color = Color(0.604, 0.416, 0.18)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_width_bottom = 2
	box.border_color = color
	box.content_margin_left = 4.0
	return box
