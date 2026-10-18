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
## Degrees past a sector edge before the facing index changes.
const FACING_HYSTERESIS_DEG := 3.0

## Pixels per second on screen with no modifiers. StatBlock.MOVE_SPEED
## replaces this in week 2; tuned numbers are written back to the spec.
const BASE_MOVE_SPEED := 120.0
## Reach full speed, or stop, in about 4 physics frames at 60 Hz.
const MOVE_ACCEL := BASE_MOVE_SPEED * 15.0
const MOVE_FRICTION := BASE_MOVE_SPEED * 15.0

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

## Raw movement input in input space (W is (0, -1)). Set by the owning
## peer's input layer, replicated to the host through InputSync.
var move_input: Vector2 = Vector2.ZERO
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
@onready var state_machine: StateMachine = $StateMachine
@onready var sprite: AnimatedSprite2D = $Sprite
@onready var weapon_pivot: Node2D = $WeaponPivot
@onready var input_sync: MultiplayerSynchronizer = $InputSync
@onready var state_sync: MultiplayerSynchronizer = $StateSync
@onready var interact_area: Area2D = $InteractArea


func _physics_process(_delta: float) -> void:
	# Only the owning peer reads hardware input. Remote copies receive
	# move_input and aim_position through InputSync (W1-B9). Runs before the
	# StateMachine child steps, so states see this frame's input.
	if is_local:
		move_input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
		aim_position = get_global_mouse_position()


## Current move speed in px/s. Reads StatBlock.MOVE_SPEED from week 2.
func move_speed() -> float:
	return BASE_MOVE_SPEED


## Points the character along a screen-space direction, with hysteresis so
## the sprite does not flicker on a sector boundary.
func set_facing(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	facing = dir.normalized()
	facing_index = Iso.facing_index(facing, facing_index, FACING_HYSTERESIS_DEG)


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
