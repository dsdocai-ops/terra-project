class_name FriendlyUnit
extends CharacterBody2D
## A unit on the player's side that is not the player: a clone, a minion or a
## turret (SPEC-combat-core "Team": PLAYER also covers minions and turrets). Owned
## by combat-core; Shadow Clones is the first user. Sync: the host owns the unit.
## The host runs the lifetime, the follow and every hit the unit lands, and it
## sends the unit's global_position to every peer on each advance, as one
## unreliable_ordered RPC (_sync_position, authority = host). A client's copy
## copies that position, and it never moves on its own. Hurtbox.receive
## early-returns on clients, so a client's copy only shows the unit.
## The RPC resolves the copy by node path, so a unit must be named the same on
## both peers before it enters the tree (ShadowClonesCast names its clones).
##
## The lifetime and the swing window run in TimeManager-scaled time of the owner,
## so a slowed owner's units slow with them. Health, StatBlock and Hurtbox are
## built in _ready when the scene does not have them, so every unit gets the same
## parts. A unit whose Health runs out frees itself.

const TEAM: Team.Kind = Team.Kind.PLAYER
const MAX_HP: float = 30.0
const HURTBOX_RADIUS: float = 12.0
const FOLLOW_SPEED: float = 220.0
## Inside this distance from the owner the unit stops, so it does not sit on top.
const FOLLOW_DISTANCE: float = 40.0
const MIN_REACH: float = 1.0
const SWING_HITBOX_NAME: String = "SwingHitbox"
const SHAPE_NODE: String = "Shape"

## The player this unit belongs to, the point it follows, and the owner whose
## time scale runs it. Null for a unit with no owner.
var owner_player: Player = null
## Seconds of owner-scaled time left before the unit frees itself.
var lifetime: float = 0.0
## Whether the unit steps toward its owner each advance.
var follow_owner: bool = true

## Seconds of owner-scaled time the current swing stays live. Zero when none is.
var _swing_left: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	_ensure_parts()


func _physics_process(delta: float) -> void:
	advance(delta)


## Sets the owner and the lifetime. Call before the unit enters the tree, or right
## after.
func setup(owner_node: Player, seconds: float) -> void:
	owner_player = owner_node
	lifetime = maxf(seconds, 0.0)


## Runs the unit's clock for `delta` seconds of owner-scaled time: the swing
## window closes when its time is spent, the unit frees itself when its lifetime
## is spent, and when following it takes one step toward the owner. Public so
## tests can drive it without physics frames. Host only; a client's copy does
## nothing here.
func advance(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var scaled: float = delta * TimeManager.scale_for(_timed_node())
	if _swing_left > 0.0:
		_swing_left -= scaled
		if _swing_left <= 0.0:
			_end_swing()
	lifetime -= scaled
	if lifetime <= 0.0:
		queue_free()
		return
	if follow_owner:
		_follow(scaled)
	_send_position()


## Host -> clients: the unit's position, so every copy sits where the host's unit
## is. Sent on each advance, so a copy also gets the spawn point right at once.
@rpc("authority", "call_remote", "unreliable_ordered")
func _sync_position(at: Vector2) -> void:
	global_position = at


## Host only: sends the position to every connected peer. Returns false and sends
## nothing with no peers, so a single-player run and the unit tests make no RPC.
func _send_position() -> bool:
	if multiplayer.get_peers().is_empty():
		return false
	_sync_position.rpc(global_position)
	return true


## Host only: turns on a melee hitbox `reach` pixels across around the unit for
## `active_seconds`, and hands it a copy of `template` as its hit. A swing still
## running is replaced. Returns the hitbox, so a test can drive it by hand.
func strike_with(template: HitInfo, reach: float, active_seconds: float) -> Hitbox:
	var hitbox := _swing_hitbox()
	hitbox.active = false
	hitbox.template = template.copy()
	var circle := CircleShape2D.new()
	circle.radius = maxf(reach, MIN_REACH)
	(hitbox.get_node(SHAPE_NODE) as CollisionShape2D).shape = circle
	hitbox.active = true
	_swing_left = maxf(active_seconds, 0.0)
	return hitbox


## One step toward the owner, stopping at FOLLOW_DISTANCE from it.
func _follow(scaled: float) -> void:
	if owner_player == null or not owner_player.is_inside_tree():
		return
	var target: Vector2 = owner_player.global_position
	var offset: Vector2 = global_position - target
	if offset.length() <= FOLLOW_DISTANCE:
		return
	var stop_at: Vector2 = target + offset.normalized() * FOLLOW_DISTANCE
	global_position = global_position.move_toward(stop_at, FOLLOW_SPEED * scaled)


func _end_swing() -> void:
	_swing_left = 0.0
	var hitbox := get_node_or_null(SWING_HITBOX_NAME) as Hitbox
	if hitbox != null:
		hitbox.active = false


## The swing hitbox, made on first use so a unit that never swings has none.
func _swing_hitbox() -> Hitbox:
	var hitbox := get_node_or_null(SWING_HITBOX_NAME) as Hitbox
	if hitbox == null:
		hitbox = Hitbox.new()
		hitbox.name = SWING_HITBOX_NAME
		hitbox.team = TEAM
		var shape_node := CollisionShape2D.new()
		shape_node.name = SHAPE_NODE
		hitbox.add_child(shape_node)
		add_child(hitbox)
	return hitbox


## Adds whichever of StatBlock, Health and Hurtbox the scene does not have. The
## order matters: Health reads StatBlock when it is ready.
func _ensure_parts() -> void:
	if get_node_or_null("StatBlock") == null:
		var stats := StatBlock.new()
		stats.name = "StatBlock"
		stats.base = {StatBlock.Stat.MAX_HP: MAX_HP}
		add_child(stats)
	if get_node_or_null("Health") == null:
		var health := Health.new()
		health.name = "Health"
		add_child(health)
		health.died.connect(_on_died)
	if get_node_or_null("Hurtbox") == null:
		var hurtbox := Hurtbox.new()
		hurtbox.name = "Hurtbox"
		hurtbox.team = TEAM
		var shape_node := CollisionShape2D.new()
		shape_node.name = SHAPE_NODE
		var circle := CircleShape2D.new()
		circle.radius = HURTBOX_RADIUS
		shape_node.shape = circle
		hurtbox.add_child(shape_node)
		add_child(hurtbox)


func _on_died(_hit: HitInfo) -> void:
	queue_free()


## The node whose TimeManager scale runs the unit: its owner, or the unit itself.
func _timed_node() -> Node:
	if owner_player != null:
		return owner_player
	return self
