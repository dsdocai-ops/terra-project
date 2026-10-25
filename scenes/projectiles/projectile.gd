class_name Projectile
extends Hitbox
## A straight-flying projectile for both teams (SPEC-combat-core `Projectile`).
## Owned by combat-core. Sync: the host owns flight and damage; StateSync
## replicates `synced_position`, `synced_velocity`, `owner_peer_id` and
## `hostile`, and clients only present that pose. No pooling yet (a later
## perf pass): bolts are spawned and freed through ProjectileSpawner.
## Placeholder art: a small coloured diamond.

const WALL_MASK: int = 1
const PLAYER_COLOR: Color = Color(1.0, 0.9, 0.5, 1.0)
const ENEMY_COLOR: Color = Color(1.0, 0.45, 0.2, 1.0)

var synced_position: Vector2 = Vector2.ZERO
var synced_velocity: Vector2 = Vector2.ZERO
var owner_peer_id: int = 1
## True for enemy projectiles; replicated so clients tint them.
var hostile: bool = false:
	set(value):
		hostile = value
		_apply_color()

var _distance_left: float = 400.0
var _pierce_left: int = 0
var _body: Polygon2D = null


func _ready() -> void:
	super._ready()
	_body = get_node_or_null("Body") as Polygon2D
	_apply_color()
	synced_position = position
	hit_connected.connect(_on_hit_connected)


## Host. Arms the projectile: `hit` is its damage template.
func launch(hit: HitInfo, side: Team.Kind, max_range: float, pierce: int) -> void:
	team = side
	hostile = side == Team.Kind.ENEMY
	template = hit
	_distance_left = max_range
	_pierce_left = pierce
	hit_once_per_target = true
	active = true


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		position = synced_position
		return
	var step: Vector2 = synced_velocity * delta
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step, WALL_MASK)
	var blocked: Dictionary = space.intersect_ray(query)
	if not blocked.is_empty():
		queue_free()
		return
	position += step
	synced_position = position
	_distance_left -= step.length()
	if _distance_left <= 0.0:
		queue_free()


func _on_hit_connected(_hurtbox: Hurtbox, _hit: HitInfo) -> void:
	if _pierce_left <= 0:
		queue_free()
		return
	_pierce_left -= 1


func _apply_color() -> void:
	if _body != null:
		_body.color = ENEMY_COLOR if hostile else PLAYER_COLOR
