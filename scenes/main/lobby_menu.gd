class_name LobbyMenu
extends Control
## The co-op lobby: a list of servers found on the local network with Join
## buttons, a join-by-address row, and a host form with a server name and an
## optional password. Owned by ui-hud. Sync: none; it only gathers input and
## emits it, `main.gd` talks to NetworkManager.
## Built in code (like the other menu screens it matches in look): the node
## tree is small and every row is generated from the server list.

signal host_requested(server_name: String, password: String)
signal join_requested(address: String, port: int, password: String)
signal back_pressed()

const THEME_PATH: String = "res://assets/ui/theme.tres"
const PARCHMENT: Color = Color(0.910, 0.847, 0.690)
const GOLD: Color = Color(0.949, 0.757, 0.306)
const MUTED: Color = Color(0.61, 0.54, 0.41)
const DANGER: Color = Color(0.88, 0.48, 0.42)
const PANEL_BG: Color = Color(0.14, 0.118, 0.086, 0.96)
const PANEL_BORDER: Color = Color(0.42, 0.353, 0.235)
const DEFAULT_SERVER_NAME: String = "Mine crew"
const MAX_NAME_LENGTH: int = LobbyDiscovery.MAX_NAME_LENGTH

var discovery: LobbyDiscovery = null

var _rows: VBoxContainer = null
var _empty_label: Label = null
var _scan_label: Label = null
var _address_field: LineEdit = null
var _name_field: LineEdit = null
var _no_password_box: CheckBox = null
var _password_field: LineEdit = null
var _host_error: Label = null
var _status: Label = null
var _prompt: PanelContainer = null
var _prompt_title: Label = null
var _prompt_field: LineEdit = null
var _prompt_error: Label = null
var _prompt_target: Dictionary = {}


func _ready() -> void:
	theme = load(THEME_PATH) as Theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	discovery = LobbyDiscovery.new()
	add_child(discovery)
	discovery.servers_changed.connect(_refresh_rows)
	_build()
	hide()


## Shows the lobby and starts looking for servers. `address` pre-fills the
## join-by-address field.
func open(address: String = "") -> void:
	if not address.is_empty():
		_address_field.text = address
	_status.text = ""
	_host_error.text = ""
	_prompt.hide()
	show()
	discovery.start_browsing()
	_refresh_rows()
	_name_field.grab_focus()


func close() -> void:
	discovery.stop()
	hide()


func show_error(text: String) -> void:
	_status.text = text


## Asks for a password for a server that turned the player away (or is known
## to be locked), then re-emits `join_requested` with it.
func ask_password(address: String, port: int, message: String = "") -> void:
	_status.text = ""
	_prompt_target = {"address": address, "port": port}
	_prompt_title.text = "Join %s" % address
	_prompt_field.text = ""
	_prompt_error.text = message
	_prompt.show()
	_prompt_field.grab_focus()


## Esc closes the password prompt, then the lobby.
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _prompt.visible:
		_prompt.hide()
	else:
		_on_back()


# --- validation (pure, so it is testable) -------------------------------------


## The reason a host form cannot start a server, or "" when it can.
static func host_error(server_name: String, no_password: bool, password: String) -> String:
	if server_name.strip_edges().is_empty():
		return "Name your server."
	if not no_password and password.is_empty():
		return "Enter a password, or tick No password."
	return ""


## Splits "host" or "host:port" into the address and port.
static func parse_address(text: String) -> Dictionary:
	var trimmed: String = text.strip_edges()
	var port: int = NetworkManager.DEFAULT_PORT
	var colon: int = trimmed.rfind(":")
	if colon > 0 and trimmed.count(":") == 1:
		var port_text: String = trimmed.substr(colon + 1)
		if port_text.is_valid_int():
			port = clampi(port_text.to_int(), 1, 65535)
			trimmed = trimmed.left(colon)
	return {"address": trimmed, "port": port}


# --- building -----------------------------------------------------------------


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.02, 0.015, 0.97)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	margin.add_child(columns)
	columns.add_child(_build_list_panel())
	columns.add_child(_build_host_panel())
	_prompt = _build_prompt()
	add_child(_prompt)


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL_BG
	box.border_color = PANEL_BORDER
	box.set_border_width_all(2)
	box.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", box)
	return panel


func _label(text: String, color: Color = PARCHMENT, size: int = 12) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)
	return label


func _button(text: String, handler: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(handler)
	button.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05) if primary else PARCHMENT)
	button.add_theme_color_override("font_hover_color", Color(0.1, 0.08, 0.05) if primary else GOLD)
	var normal := StyleBoxFlat.new()
	normal.bg_color = GOLD if primary else Color(0.2, 0.17, 0.12)
	normal.border_color = GOLD if primary else PANEL_BORDER
	normal.set_border_width_all(2)
	normal.set_content_margin_all(5)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("pressed", normal)
	button.add_theme_stylebox_override("focus", normal)
	return button


## Gives the checkbox a visible box on the dark panel (the theme's default is
## near-black on near-black).
func _style_checkbox(box: CheckBox) -> void:
	var size: int = 14
	var off := Image.create(size, size, false, Image.FORMAT_RGBA8)
	off.fill(PANEL_BORDER)
	off.fill_rect(Rect2i(2, 2, size - 4, size - 4), Color(0.08, 0.065, 0.045))
	var on := off.duplicate() as Image
	on.fill_rect(Rect2i(4, 4, size - 8, size - 8), GOLD)
	box.add_theme_icon_override("unchecked", ImageTexture.create_from_image(off))
	box.add_theme_icon_override("checked", ImageTexture.create_from_image(on))


func _field(placeholder: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.add_theme_color_override("font_color", PARCHMENT)
	field.add_theme_font_size_override("font_size", 12)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.065, 0.045)
	box.border_color = PANEL_BORDER
	box.set_border_width_all(2)
	box.content_margin_left = 6.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	field.add_theme_stylebox_override("normal", box)
	field.add_theme_stylebox_override("focus", box)
	return field


func _build_list_panel() -> Control:
	var panel: PanelContainer = _panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title: Label = _label("CO-OP LOBBY", GOLD, 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_scan_label = _label("Scanning the local network…", MUTED)
	header.add_child(_scan_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	holder.add_child(_rows)
	_empty_label = _label("No servers found. Host one, or join by address below.", MUTED)
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	holder.add_child(_empty_label)
	_status = _label("", DANGER)
	column.add_child(_status)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 6)
	column.add_child(join_row)
	_address_field = _field("192.168.1.20")
	_address_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_address_field.text_submitted.connect(func(_t: String) -> void: _on_join_address())
	join_row.add_child(_address_field)
	join_row.add_child(_button("Join address", _on_join_address))
	join_row.add_child(_button("Refresh", _on_refresh))
	join_row.add_child(_button("Back", _on_back))
	return panel


func _build_host_panel() -> Control:
	var panel: PanelContainer = _panel()
	panel.custom_minimum_size = Vector2(250, 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(_label("HOST A SERVER", GOLD, 16))
	column.add_child(_label("Server name", MUTED))
	_name_field = _field(DEFAULT_SERVER_NAME)
	_name_field.text = DEFAULT_SERVER_NAME
	_name_field.max_length = MAX_NAME_LENGTH
	column.add_child(_name_field)
	_no_password_box = CheckBox.new()
	_no_password_box.text = "No password"
	_no_password_box.add_theme_color_override("font_color", PARCHMENT)
	_no_password_box.add_theme_font_size_override("font_size", 12)
	_style_checkbox(_no_password_box)
	_no_password_box.toggled.connect(_on_no_password_toggled)
	column.add_child(_no_password_box)
	column.add_child(_label("Password", MUTED))
	_password_field = _field("Choose a password")
	_password_field.secret = true
	_password_field.text_submitted.connect(func(_t: String) -> void: _on_start_server())
	column.add_child(_password_field)
	_host_error = _label("", DANGER)
	_host_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_host_error)
	column.add_child(_button("Start server", _on_start_server, true))
	return panel


func _build_prompt() -> PanelContainer:
	var panel: PanelContainer = _panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(280, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	_prompt_title = _label("Join", GOLD, 16)
	column.add_child(_prompt_title)
	_prompt_field = _field("Server password")
	_prompt_field.secret = true
	_prompt_field.text_submitted.connect(func(_t: String) -> void: _on_prompt_join())
	column.add_child(_prompt_field)
	_prompt_error = _label("", DANGER)
	column.add_child(_prompt_error)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.add_child(_button("Join", _on_prompt_join, true))
	buttons.add_child(_button("Cancel", func() -> void: _prompt.hide()))
	column.add_child(buttons)
	panel.hide()
	return panel


# --- the list -----------------------------------------------------------------


func _refresh_rows() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.queue_free()
	var count: int = discovery.servers.size()
	for key: String in discovery.servers:
		_rows.add_child(_server_row(discovery.servers[key]))
	_empty_label.visible = count == 0
	_scan_label.text = "%d found" % count if count > 0 else "Scanning the local network…"


func _server_row(info: LobbyServerInfo) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label: Label = _label(info.server_name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	row.add_child(name_label)
	row.add_child(_label("Locked" if info.locked else "Open", GOLD if info.locked else MUTED))
	row.add_child(_label("%d/%d" % [info.players, info.max_players]))
	var join: Button = _button("Full" if info.is_full() else "Join", _on_join_server.bind(info))
	join.disabled = info.is_full()
	row.add_child(join)
	return row


# --- handlers -----------------------------------------------------------------


func _on_join_server(info: LobbyServerInfo) -> void:
	_status.text = ""
	if info.locked:
		ask_password(info.address, info.port)
		return
	join_requested.emit(info.address, info.port, "")


func _on_join_address() -> void:
	var target: Dictionary = parse_address(_address_field.text)
	if not NetworkManager.looks_like_address(String(target["address"])):
		_status.text = "Enter the host's address, like 192.168.1.20."
		return
	_status.text = ""
	join_requested.emit(String(target["address"]), int(target["port"]), "")


func _on_prompt_join() -> void:
	if _prompt_field.text.is_empty():
		_prompt_error.text = "Enter the server password."
		return
	_prompt.hide()
	join_requested.emit(String(_prompt_target["address"]), int(_prompt_target["port"]), _prompt_field.text)


func _on_refresh() -> void:
	_status.text = ""
	discovery.start_browsing()


func _on_back() -> void:
	close()
	back_pressed.emit()


func _on_no_password_toggled(pressed: bool) -> void:
	_password_field.editable = not pressed
	_password_field.modulate.a = 0.4 if pressed else 1.0


func _on_start_server() -> void:
	var error: String = host_error(_name_field.text, _no_password_box.button_pressed, _password_field.text)
	_host_error.text = error
	if not error.is_empty():
		return
	var password: String = "" if _no_password_box.button_pressed else _password_field.text
	host_requested.emit(_name_field.text.strip_edges(), password)
