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

## Who this copy of the player is on this peer (SPEC-networking).
enum SyncRole {
	HOST_PUBLISHES,       ## the host simulates and writes synced_* every frame
	LOCAL_PREDICTS,       ## the owning client simulates and reconciles against acked host poses
	REMOTE_INTERPOLATES,  ## another peer's copy: follows synced_* and plays synced anims
}

## Prediction error beyond which the local player snaps to the host position.
const SNAP_DISTANCE := 64.0
## Prediction errors at or below this many pixels are left alone, so float
## noise between peers never nudges a player.
const RECONCILE_DEADZONE := 0.5
## Physics ticks of predicted positions kept for reconcile (2 s at 60 Hz).
const PREDICTION_HISTORY := 120
## Remote copies snap when they fall this far behind (spawn, teleport).
const INTERPOLATE_SNAP_DISTANCE := 512.0
## Per-second rates for the exponential approach toward the synced pose.
const RECONCILE_RATE := 10.0
const INTERPOLATE_RATE := 15.0

## Degrees past a sector edge before the facing index changes (see Facing).
const FACING_HYSTERESIS_DEG := 3.0

## Pixels per second on screen with no modifiers. StatBlock.MOVE_SPEED
## replaces this in week 2; tuned numbers are written back to the spec.
const BASE_MOVE_SPEED := 120.0
## Time to reach full speed from rest, and to stop from full speed: 4 physics
## frames at 60 Hz. Expressed as time so a speed buff keeps the same feel.
const ACCEL_SECONDS := 4.0 / 60.0
const STOP_SECONDS := 4.0 / 60.0

## Multiplayer peer that owns this player's input. 1 is the host, 0 means
## not assigned yet; the spawner sets it before adding the node to the tree.
var peer_id: int = 0:
	set(value):
		peer_id = value
		refresh_authority()

## TODO(classes-characters): retype to CharacterData when it exists.
var character: Resource
## TODO(classes-characters): retype to ClassData when it exists.
var class_data: Resource

var facing: Vector2 = Vector2.DOWN
var facing_index: int = 0:
	set(value):
		var clamped := posmod(value, Facing.count())
		if clamped == facing_index:
			return
		facing_index = clamped
		_replay_directional()
		facing_changed.emit(facing_index)

## Raw movement input in input space (W is (0, -1)). Set by the owning
## peer's input layer, replicated to the host through InputSync.
var move_input: Vector2 = Vector2.ZERO
## Owning peer's physics tick counter for move_input, sent with it through
## InputSync so the host can say which input its pose includes.
var input_tick: int = 0
## World position of the owning peer's cursor.
var aim_position: Vector2 = Vector2.ZERO
var is_downed: bool = false
var is_local: bool:
	get:
		return is_inside_tree() and peer_id == multiplayer.get_unique_id()

## True where this player's state machine should run: on the host for every
## player, and on the owning client for its own player (prediction). Remote
## copies on a client only present what StateSync replicates.
var simulates: bool:
	get:
		return is_inside_tree() and (multiplayer.is_server() or is_local)

var dodge_charges: int = 1
var dodge_distance_mult: float = 1.0
var revive_speed_mult: float = 1.0

## Host-written pose, replicated by StateSync. Clients reconcile or
## interpolate toward it; nobody replicates `position` directly.
var synced_position: Vector2 = Vector2.ZERO
var synced_velocity: Vector2 = Vector2.ZERO
## The owner's input_tick that synced_position includes. The owning client
## compares synced_position with its own prediction for this tick.
var acked_input_tick: int = 0
## Base animation name ("idle", "walk") without the facing suffix. Replicated
## by StateSync so remote copies play what the host plays.
var current_anim: String = "":
	set(value):
		if value == current_anim:
			return
		current_anim = value
		_replay_directional()

## Debug hook for the headless smoke (--smoke): when non-zero on a local
## player it replaces hardware input.
var debug_autowalk: Vector2 = Vector2.ZERO

## Host: input_tick of the move_input the states applied on the last tick.
var _applied_input_tick: int = 0
## Owning client: predicted position after applying each input tick.
var _predictions: Dictionary[int, Vector2] = {}
var _last_reconciled_tick: int = -1

var _perfect_dodge_window_open: bool = false
var _dodge_cooldown_left: float = 0.0
## Animation names already reported missing, so a bad name warns once.
var _missing_anims: Dictionary[StringName, bool] = {}

## Components. Typed to their real classes as each module lands.
## TODO(stats-status): stat_block -> StatBlock, status_effects -> StatusEffects
## TODO(combat-core): health -> Health, hurtbox -> Hurtbox
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


func _ready() -> void:
	refresh_authority()


## Applies `simulates` and `is_local` to the state machine: only simulating
## copies step states, and only the owning peer's copy reacts to hardware
## input. Called when peer_id changes and on ready; networking calls it
## again if authority ever moves.
func refresh_authority() -> void:
	if state_machine == null:
		return
	state_machine.set_physics_process(simulates)
	state_machine.set_process_unhandled_input(is_local)
	if is_inside_tree():
		physics_interpolation_mode = interpolation_mode_for(sync_role())


## Simulating copies move on physics ticks and are drawn interpolated
## between them. Remote copies already ease toward synced_position every
## rendered frame in _process, so tick interpolation on top would only lag
## and step them.
static func interpolation_mode_for(role: SyncRole) -> Node.PhysicsInterpolationMode:
	if role == SyncRole.REMOTE_INTERPOLATES:
		return Node.PHYSICS_INTERPOLATION_MODE_OFF
	return Node.PHYSICS_INTERPOLATION_MODE_INHERIT


## Runs before the StateMachine child steps, so states see this tick's
## input and an already reconciled position.
func _physics_process(delta: float) -> void:
	if sync_role() == SyncRole.LOCAL_PREDICTS:
		# `position` is the result of last tick's input. Correct it on the
		# tick, before this tick's movement builds on it.
		record_prediction(input_tick, position)
		reconcile(acked_input_tick, synced_position, delta)
	# Only the owning peer reads hardware input. The host receives
	# move_input, input_tick and aim_position through InputSync.
	if is_local:
		input_tick += 1
		if debug_autowalk != Vector2.ZERO:
			move_input = debug_autowalk
		else:
			move_input = Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
			aim_position = get_global_mouse_position()
	if multiplayer.is_server():
		# move_input and input_tick arrive in the same InputSync packet, so
		# this is the tick of the input the states apply now.
		_applied_input_tick = input_tick


func _process(delta: float) -> void:
	match sync_role():
		SyncRole.HOST_PUBLISHES:
			publish_state()
		SyncRole.REMOTE_INTERPOLATES:
			interpolate_toward(synced_position, delta)
			velocity = synced_velocity


func sync_role() -> SyncRole:
	if multiplayer.is_server():
		return SyncRole.HOST_PUBLISHES
	return SyncRole.LOCAL_PREDICTS if is_local else SyncRole.REMOTE_INTERPOLATES


## Host: copy the simulated pose into the replicated fields, stamped with
## the owner's input tick it includes.
func publish_state() -> void:
	synced_position = position
	synced_velocity = velocity
	acked_input_tick = _applied_input_tick


## Owning client: remember where prediction put the player after `tick`.
func record_prediction(tick: int, predicted: Vector2) -> void:
	_predictions[tick] = predicted
	_predictions.erase(tick - PREDICTION_HISTORY)


## Owning client: compare the host's pose for an acknowledged input tick
## with this peer's prediction for the same tick, and shift the present by
## the difference. The host pose is a round trip old, so comparing it with
## the current position instead drags a walking player back every frame.
## Small errors ease out over several acks; large ones snap.
func reconcile(acked_tick: int, host_position: Vector2, delta: float) -> void:
	if acked_tick <= _last_reconciled_tick:
		return
	_last_reconciled_tick = acked_tick
	if not _predictions.has(acked_tick):
		# Nothing to compare with (just spawned, or the ack is older than
		# the history). Only a gross mismatch is worth acting on.
		if position.distance_to(host_position) > SNAP_DISTANCE:
			_snap_to(host_position)
		return
	var error := host_position - _predictions[acked_tick]
	for tick: int in _predictions.keys():
		if tick <= acked_tick:
			_predictions.erase(tick)
	if error.length() > SNAP_DISTANCE:
		_snap_to(position + error)
		return
	if error.length() <= RECONCILE_DEADZONE:
		return
	_shift_prediction(error * (1.0 - exp(-RECONCILE_RATE * delta)))


## Moves the present and every unacknowledged prediction by `correction`,
## so the next ack is compared against the corrected path.
func _shift_prediction(correction: Vector2) -> void:
	position += correction
	for tick: int in _predictions.keys():
		_predictions[tick] += correction


func _snap_to(target: Vector2) -> void:
	_shift_prediction(target - position)
	reset_physics_interpolation()


## Remote copy: follow the host's pose smoothly, snapping if far behind.
func interpolate_toward(target: Vector2, delta: float) -> void:
	if position.distance_to(target) > INTERPOLATE_SNAP_DISTANCE:
		position = target
		return
	position = position.lerp(target, 1.0 - exp(-INTERPOLATE_RATE * delta))


## Current move speed in px/s. Reads StatBlock.MOVE_SPEED from week 2.
func move_speed() -> float:
	return BASE_MOVE_SPEED


## Acceleration in px/s^2 toward the current move speed.
func move_accel() -> float:
	return move_speed() / ACCEL_SECONDS


## Deceleration in px/s^2 when input stops.
func move_friction() -> float:
	return move_speed() / STOP_SECONDS


## Points the character along a screen-space direction, with hysteresis so
## the sprite does not flicker on a sector boundary.
func set_facing(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	facing = dir.normalized()
	facing_index = Facing.index_for(facing, facing_index, FACING_HYSTERESIS_DEG)


## In co-op nobody may leave the shared frame. Limits `velocity` so the next
## position stays inside GameCamera.coop_bounds() of every player under the
## same container. Call before move_and_slide(). Depends only on replicated
## player positions, never on a camera, so host and predicting client agree.
func apply_coop_clamp(delta: float) -> void:
	if delta <= 0.0:
		return
	var positions := _sibling_player_positions()
	if positions.size() < 2:
		return
	var rect := GameCamera.coop_bounds(positions)
	var next := global_position + velocity * delta
	var clamped := next.clamp(rect.position, rect.end)
	velocity = (clamped - global_position) / delta


func _sibling_player_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var container := get_parent()
	if container == null:
		return positions
	for child in container.get_children():
		var p := child as Player
		if p != null:
			positions.append(p.global_position)
	return positions


func is_perfect_dodge_window() -> bool:
	return _perfect_dodge_window_open


func consume_perfect_dodge_window() -> void:
	_perfect_dodge_window_open = false


func reset_dodge_cooldown() -> void:
	_dodge_cooldown_left = 0.0


## Plays `<anim>_<dir>` for the current facing, e.g. "walk" becomes "walk_ne".
## Call it on state changes only; facing changes replay it automatically.
func play_directional(anim: String) -> void:
	var anim_name := StringName("%s_%s" % [anim, Facing.suffix(facing_index)])
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim_name):
		if not _missing_anims.has(anim_name):
			_missing_anims[anim_name] = true
			push_warning("Player: missing animation %s" % anim_name)
		return
	current_anim = anim
	if sprite.animation != anim_name:
		sprite.play(anim_name)


func _replay_directional() -> void:
	if current_anim != "" and sprite != null:
		play_directional(current_anim)


## Client asks the host to revive `target`. Filled in by networking week 3.
func request_revive(_target: Player) -> void:
	pass
