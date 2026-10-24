extends PlayerState
## A dodge roll: a fixed-speed burst with i-frames (SPEC-player-controller
## `Dodge`). A hit that lands during the i-frames is blocked, which opens the
## perfect-dodge window on `Player` (set by `Hurtbox.blocked_during_dodge`).
## Owned by player-controller (W2-A8). Sync: like Move, it runs on the host and
## the owning client; the host's Hurtbox flags decide what is blocked.

const DURATION_SECONDS: float = 0.28
const IFRAME_SECONDS: float = 0.22
const SPEED_MULT: float = 2.6

var _dir: Vector2 = Vector2.DOWN
var _elapsed: float = 0.0


func enter(_from: StringName) -> void:
	_dir = player.pending_dodge_dir
	if player.move_input != Vector2.ZERO:
		_dir = Iso.input_to_world(player.move_input).normalized()
	if _dir == Vector2.ZERO:
		_dir = player.facing
	_elapsed = 0.0
	player.set_facing(_dir)
	player.begin_dodge()


func exit(_to: StringName) -> void:
	player.end_dodge()


func physics_update(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= IFRAME_SECONDS and player.hurtbox != null:
		player.hurtbox.dodge_invulnerable = false
		if player.hit_iframes_left <= 0.0:
			player.hurtbox.invulnerable = false
	player.velocity = _dir * player.move_speed() * SPEED_MULT * player.dodge_distance_mult
	player.apply_coop_clamp(delta)
	player.move_and_slide()
	if _elapsed >= DURATION_SECONDS:
		var next: StringName = &"Move" if player.move_input != Vector2.ZERO else &"Idle"
		if machine.change_to(next):
			machine.current.physics_update(0.0)
