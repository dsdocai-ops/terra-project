class_name PlaceholderMenu
extends Control
## The main menu: Play Solo and one Co-op entry (opens the lobby), drawn as carved
## gold-and-parchment text with a pickaxe pointing at the highlighted line, over a
## dark vignette, in the UI pixel font. Owned by foundation (look: ui-hud, Dev B).
## Sync: none. Codex and Settings join the list in weeks 11 and 12.

signal solo_pressed()
signal coop_pressed()
signal settings_pressed()
signal codex_pressed()
signal quit_pressed()

const THEME_PATH := "res://assets/ui/theme.tres"
const PARCHMENT := Color(0.910, 0.847, 0.690)
const GOLD := Color(0.949, 0.757, 0.306)
const BRONZE_SHADOW := Color(0.35, 0.24, 0.1)
const TITLE_SIZE: int = 48
const ITEM_SIZE: int = 16
const POINTER_SCALE: int = 2
## Left indent per row so the list bows out like the pit wall.
const INDENTS: Array[int] = [0, 10, 16, 18, 16, 10, 0]

@onready var status_label: Label = %Status
@onready var solo_button: Button = %Solo
@onready var coop_button: Button = %Coop
@onready var settings_button: Button = %Settings
@onready var codex_button: Button = %Codex
@onready var quit_button: Button = %Quit

var _pointer: Texture2D


func _ready() -> void:
	# The menu lives outside the HUD, so it takes the project theme (and with it
	# the pixel font) itself instead of falling back to Godot's default font.
	theme = load(THEME_PATH) as Theme
	solo_button.pressed.connect(func() -> void: solo_pressed.emit())
	coop_button.pressed.connect(func() -> void: coop_pressed.emit())
	settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	codex_button.pressed.connect(func() -> void: codex_pressed.emit())
	quit_button.pressed.connect(func() -> void: quit_pressed.emit())
	_pointer = _make_pointer()
	_add_backdrop()
	_style()
	solo_button.grab_focus()


func set_status(text: String) -> void:
	status_label.text = text


## The pickaxe pointer at 2x, so its pixels match the 2px UI grid.
func _make_pointer() -> Texture2D:
	var source: Texture2D = UiPalette.icon("pointer")
	if source == null:
		return null
	var image: Image = source.get_image()
	image.resize(image.get_width() * POINTER_SCALE, image.get_height() * POINTER_SCALE, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)


## A radial darkening behind the text, so the title reads over any floor.
func _add_backdrop() -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.04, 0.03, 0.02, 0.35), Color(0.04, 0.03, 0.02, 0.9)])
	gradient.offsets = PackedFloat32Array([0.25, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.3, 0.45)
	texture.fill_to = Vector2(1.0, 0.45)
	texture.width = 256
	texture.height = 144
	var backdrop := TextureRect.new()
	backdrop.texture = texture
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	move_child(backdrop, 0)


func _style() -> void:
	var margin := $Center as MarginContainer
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := $Center/Panel as PanelContainer
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var rows := $Center/Panel/Rows as VBoxContainer
	rows.add_theme_constant_override("separation", 6)
	var title := $Center/Panel/Rows/Title as Label
	title.text = "SINKHOLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_font_size_override("font_size", TITLE_SIZE)
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_color_override("font_shadow_color", BRONZE_SHADOW)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("shadow_offset_x", 0)
	var tagline := Label.new()
	tagline.text = "A DIVE FOR UP TO FOUR"
	tagline.add_theme_color_override("font_color", PARCHMENT)
	tagline.add_theme_constant_override("line_spacing", 0)
	rows.add_child(tagline)
	rows.move_child(tagline, title.get_index() + 1)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 28)
	rows.add_child(spacer)
	rows.move_child(spacer, tagline.get_index() + 1)
	var buttons: Array[Button] = [solo_button, coop_button, settings_button, codex_button, quit_button]
	for index: int in buttons.size():
		_carve(buttons[index], INDENTS[index + 1])
	status_label.add_theme_color_override("font_color", Color(0.85, 0.35, 0.3))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


## Turns a Button into carved text: no box, left aligned, gold when highlighted,
## with the pickaxe pointer in the gutter on the highlighted line.
func _carve(button: Button, indent: int) -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = float(indent) + 36.0
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, empty)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("h_separation", 6)
	button.add_theme_font_size_override("font_size", ITEM_SIZE)
	button.add_theme_color_override("font_color", PARCHMENT)
	button.add_theme_color_override("font_hover_color", GOLD)
	button.add_theme_color_override("font_focus_color", GOLD)
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_color_override("icon_normal_color", Color.WHITE)
	button.focus_entered.connect(_on_focus.bind(button, indent))
	button.focus_exited.connect(_on_unfocus.bind(button, indent))
	button.mouse_entered.connect(button.grab_focus)


## The pointer is the button's icon while it is focused; its margin shrinks by the
## icon's width so the text does not shift.
func _on_focus(button: Button, indent: int) -> void:
	button.icon = _pointer
	var margin: float = maxf(float(indent) + 36.0 - (_pointer.get_width() + 6.0 if _pointer != null else 0.0), 0.0)
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		(button.get_theme_stylebox(state) as StyleBoxEmpty).content_margin_left = margin


func _on_unfocus(button: Button, indent: int) -> void:
	button.icon = null
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		(button.get_theme_stylebox(state) as StyleBoxEmpty).content_margin_left = float(indent) + 36.0


func _underline(color: Color = Color(0.604, 0.416, 0.18)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.border_width_bottom = 2
	box.border_color = color
	box.content_margin_left = 4.0
	return box
