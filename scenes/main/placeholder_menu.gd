class_name PlaceholderMenu
extends Control
## Week 1 stand-in for the main menu (ui-hud, week 5): Play Solo, Host, and
## Join with an IP field. Owned by foundation. Sync: none.

signal solo_pressed()
signal host_pressed()
signal join_pressed(ip: String)

@onready var ip_field: LineEdit = %IpField
@onready var status_label: Label = %Status
@onready var solo_button: Button = %Solo
@onready var host_button: Button = %Host
@onready var join_button: Button = %Join


func _ready() -> void:
	solo_button.pressed.connect(func() -> void: solo_pressed.emit())
	host_button.pressed.connect(func() -> void: host_pressed.emit())
	join_button.pressed.connect(func() -> void: join_pressed.emit(ip_field.text.strip_edges()))


func set_status(text: String) -> void:
	status_label.text = text
