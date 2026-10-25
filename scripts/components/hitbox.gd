class_name Hitbox
extends Area2D
## Deals a hit to every opposing `Hurtbox` it overlaps while `active`. Owned by
## combat-core. Used by melee arcs (enabled for the active frames only),
## projectiles and enemy attack patterns.
## Sync: none. `active` is host-only and not synced (SPEC-combat-core): the host
## decides when a hitbox is live, and `Hurtbox.receive` early-returns on clients
## anyway, so a client-side overlap changes nothing.

## Physics layers (project.godot layer_names): a player-side hitbox lives on
## `hitbox_player` and looks for the `enemy` layer; an enemy-side one lives on
## `hitbox_enemy` and looks for the `player` layer.
const LAYER_PLAYER_BODY: int = 1 << 1
const LAYER_ENEMY_BODY: int = 1 << 2
const LAYER_HITBOX_PLAYER: int = 1 << 3
const LAYER_HITBOX_ENEMY: int = 1 << 4

## Emitted for each hurtbox that took a hit from this hitbox.
signal hit_connected(hurtbox: Hurtbox, hit: HitInfo)

@export var team: Team.Kind = Team.Kind.PLAYER:
	set(value):
		team = value
		_apply_layers()
## The payload the attacker builds. Each target gets `template.copy()`.
var template: HitInfo = null
## One hit per target per activation (a melee arc must not tick every frame).
@export var hit_once_per_target: bool = true
## Whether the hitbox can hit. Switching it on starts a fresh set of targets.
var active: bool = false:
	set(value):
		if value == active:
			return
		active = value
		if active:
			_already_hit.clear()
		set_deferred("monitoring", active)

var _already_hit: Array[Hurtbox] = []


func _ready() -> void:
	_apply_layers()
	monitorable = false
	monitoring = active
	area_entered.connect(_on_area_entered)


func _apply_layers() -> void:
	collision_layer = LAYER_HITBOX_PLAYER if team != Team.Kind.ENEMY else LAYER_HITBOX_ENEMY
	collision_mask = LAYER_PLAYER_BODY if team == Team.Kind.ENEMY else LAYER_ENEMY_BODY


func _on_area_entered(area: Area2D) -> void:
	var hurtbox := area as Hurtbox
	if hurtbox != null:
		try_hit(hurtbox)


## Hits `hurtbox` if the hitbox is live, the sides oppose and (when
## `hit_once_per_target`) it has not been hit since activation. Returns whether
## the hurtbox took damage. Public so a test, or a caller sweeping manually, can
## drive it without physics.
func try_hit(hurtbox: Hurtbox) -> bool:
	if not active or template == null:
		return false
	if not Team.opposes(team, hurtbox.team):
		return false
	if hit_once_per_target:
		if _already_hit.has(hurtbox):
			return false
		_already_hit.append(hurtbox)
	var hit: HitInfo = template.copy()
	var connected: bool = hurtbox.receive(hit)
	if connected:
		hit_connected.emit(hurtbox, hit)
	return connected
