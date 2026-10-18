class_name Player
extends CharacterBody2D
## The player character. Owned by player-controller.
## Sync: input and presentation belong to the owning peer (InputSync,
## authority = peer_id). Position of record, HP, and downed state belong to the
## host (StateSync, authority = 1). The local player predicts its own movement
## and is corrected by StateSync. See SPEC-networking.
##
## Week 1 ships the skeleton: node layout, public fields and signals, facing
## and directional animation. Combat components are filled in week 2, downed
## and revive in week 3.

signal downed()
signal revived(by: Player)
signal dodge_started(perfect_window_open: bool)
signal dodge_finished()
signal facing_changed(index: int)

## Sprite animation suffix per facing index. Index 0 faces the camera.
const FACING_SUFFIXES: Array[StringName] = [&"s", &"sw", &"w", &"nw", &"n", &"ne", &"e", &"se"]

## Multiplayer peer that owns this player's input. 1 is the host.
var peer_id: int = 0

## CharacterData once classes-characters lands; typed Resource until then.
var character: Resource
## ClassData once classes-characters lands; typed Resource until then.
var class_data: Resource

var facing: Vector2 = Vector2.DOWN
var facing_index: int = 0:
	set(value):
		var clamped := posmod(value, FACING_SUFFIXES.size())
		if clamped == facing_index:
			return
		facing_index = clamped
		facing_changed.emit(facing_index)

## World position of the owning peer's cursor.
var aim_position: Vector2 = Vector2.ZERO
var is_downed: bool = false
var is_local: bool:
	get:
		return is_inside_tree() and peer_id == multiplayer.get_unique_id()

var dodge_charges: int = 1
var dodge_distance_mult: float = 1.0
var revive_speed_mult: float = 1.0

var _perfect_dodge_window_open: bool = false
var _dodge_cooldown_left: float = 0.0

## Components. Typed to their real classes as each module lands.
@onready var stat_block: Node = $StatBlock
@onready var health: Node = $Health
@onready var hurtbox: Area2D = $Hurtbox
@onready var status_effects: Node = $StatusEffects
@onready var state_machine: Node = $StateMachine
@onready var sprite: AnimatedSprite2D = $Sprite
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var input_sync: MultiplayerSynchronizer = $InputSync
@onready var state_sync: MultiplayerSynchronizer = $StateSync
@onready var interact_area: Area2D = $InteractArea


func _ready() -> void:
	play_directional("idle")


func is_perfect_dodge_window() -> bool:
	return _perfect_dodge_window_open


func consume_perfect_dodge_window() -> void:
	_perfect_dodge_window_open = false


func reset_dodge_cooldown() -> void:
	_dodge_cooldown_left = 0.0


## Plays `<anim>_<dir>` for the current facing, e.g. "walk" becomes "walk_ne".
func play_directional(anim: String) -> void:
	var name := StringName("%s_%s" % [anim, FACING_SUFFIXES[facing_index]])
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(name):
		if sprite.animation != name:
			sprite.play(name)
	else:
		push_warning("Player: missing animation %s" % name)


## Client asks the host to revive `target`. Filled in by networking week 3.
func request_revive(_target: Player) -> void:
	pass
