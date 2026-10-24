class_name Enemy
extends CharacterBody2D
## The one enemy scene every enemy type is built on (SPEC-enemies-ai
## `enemy_base`): configured entirely from `EnemyData`, driven by a small
## StateMachine (Idle, Chase, Attack, HitStun). Owned by enemies-ai.
## Sync: the host runs AI, attacks, HP and death; StateSync replicates
## position, animation tag, current HP, the telegraph progress and aim, and the
## spawn-time `kind`/`elite`. Clients only present that state. Placeholder art:
## a coloured body polygon.

signal died(hit: HitInfo)

const SEPARATION_RADIUS: float = 22.0
const SEPARATION_PUSH: float = 40.0
const PATH_REFRESH_SECONDS: float = 0.5
const DEATH_FADE_SECONDS: float = 0.05
const FLASH_SECONDS: float = 0.08
const GROUP: StringName = &"enemies"

var data: EnemyData = null
var kind: StringName = &""
var fight_id: int = 0
var elite: bool = false
var synced_position: Vector2 = Vector2.ZERO
var current_anim: StringName = &"idle"
## 0..1 while an attack winds up, -1 otherwise; clients draw the telegraph.
var telegraph_progress: float = -1.0
var aim_dir: Vector2 = Vector2.DOWN
## Set by the spawn director so the room can count this enemy.
var room: Room = null
var target: Node2D = null
var attack_cooldown_left: float = 0.0
var hit_stun_left: float = 0.0
var knockback_velocity: Vector2 = Vector2.ZERO
var next_attack: AttackPattern = null

var _path: PackedVector2Array = PackedVector2Array()
var _path_timer: float = 0.0
var _flash_left: float = 0.0
var _knockback_decel: float = 0.0

@onready var stat_block: StatBlock = $StatBlock
@onready var health: Health = $Health
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var machine: StateMachine = $StateMachine
@onready var telegraph: Telegraph = $Telegraph
@onready var body: Polygon2D = $Body
@onready var hitbox: Hitbox = $Hitbox
@onready var hitbox_shape: CollisionShape2D = $Hitbox/Shape


## Configures this enemy from its data. Called by the spawner on every peer
## right after instantiate(), before the node enters the tree, so Health's
## `_ready` sees the final MAX_HP.
func setup(p_kind: StringName, p_elite: bool = false) -> bool:
	kind = p_kind
	elite = p_elite
	data = EnemyData.find(kind)
	if data == null:
		push_warning("[enemy] no EnemyData for '%s'" % kind)
		return false
	var stats: StatBlock = get_node("StatBlock") as StatBlock
	stats.base = data.base_stats.duplicate()
	var biome: int = GameState.run.biome_index if GameState.run != null else maxi(GameState.remote_floor_index - 1, 0) / BiomeData.FLOORS_PER_BIOME + 1
	var max_hp: float = Scaling.enemy_max_hp(float(stats.base.get(StatBlock.Stat.MAX_HP, 20.0)), biome)
	if elite:
		max_hp = Scaling.elite_hp(max_hp)
	stats.base[StatBlock.Stat.MAX_HP] = max_hp
	var poly: Polygon2D = get_node("Body") as Polygon2D
	var r: float = data.radius * (1.3 if elite else 1.0)
	poly.polygon = PackedVector2Array([Vector2(-r, -r * 1.6), Vector2(r, -r * 1.6), Vector2(r, r * 0.5), Vector2(-r, r * 0.5)])
	poly.color = data.color.lightened(0.25) if elite else data.color
	(get_node("BodyShape") as CollisionShape2D).shape = _circle(r)
	(get_node("Hurtbox/HurtShape") as CollisionShape2D).shape = _circle(r + 2.0)
	return true


func _circle(radius: float) -> CircleShape2D:
	var shape := CircleShape2D.new()
	shape.radius = radius
	return shape


func _ready() -> void:
	add_to_group(GROUP)
	synced_position = global_position
	hurtbox.team = Team.Kind.ENEMY
	hitbox.team = Team.Kind.ENEMY
	machine.set_physics_process(multiplayer.is_server())
	if multiplayer.is_server():
		health.died.connect(_on_died)
		health.damaged.connect(_on_damaged)
		if room != null:
			room.track_enemy(self)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	attack_cooldown_left = maxf(attack_cooldown_left - delta, 0.0)
	_path_timer = maxf(_path_timer - delta, 0.0)


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		body.modulate = Color(2.0, 2.0, 2.0, 1.0) if _flash_left > 0.0 else Color.WHITE
	telegraph.progress = telegraph_progress
	telegraph.direction = aim_dir
	if multiplayer.is_server():
		synced_position = global_position
	else:
		global_position = global_position.lerp(synced_position, clampf(delta * 15.0, 0.0, 1.0))


# --- targeting and movement ----------------------------------------------------


## The nearest living player, or null.
func pick_target() -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF
	for player: Player in NetworkManager.players.values():
		if not is_instance_valid(player) or player.is_downed or player.is_dead:
			continue
		var dist: float = global_position.distance_to(player.global_position)
		if dist < best_dist:
			best_dist = dist
			best = player
	return best


## Steers toward `point` along the floor's A* path (direct when there is no
## floor), with separation from nearby enemies. Moves with `speed`.
func move_toward_point(point: Vector2, speed: float, delta: float) -> void:
	var goal: Vector2 = _next_waypoint(point)
	var dir: Vector2 = (goal - global_position).normalized()
	dir += _separation()
	velocity = dir.normalized() * speed * _time_scale()
	move_and_slide()


func stop_moving(delta: float) -> void:
	velocity = velocity.move_toward(Vector2.ZERO, 800.0 * delta)
	move_and_slide()


func _time_scale() -> float:
	return 1.0


func _next_waypoint(point: Vector2) -> Vector2:
	var world: World = GameState.world
	if world == null or world.floor_node == null or world.floor_node.astar == null:
		return point
	if _path_timer <= 0.0 or _path.is_empty():
		_path_timer = PATH_REFRESH_SECONDS
		_path = _build_path(world.floor_node.astar, point)
	while _path.size() > 0 and global_position.distance_to(_path[0]) < 10.0:
		_path.remove_at(0)
	if _path.is_empty():
		return point
	return _path[0]


func _build_path(astar: AStarGrid2D, point: Vector2) -> PackedVector2Array:
	var from: Vector2i = Iso.to_tile(global_position)
	var to: Vector2i = Iso.to_tile(point)
	var region: Rect2i = astar.region
	if not region.has_point(from) or not region.has_point(to) or astar.is_point_solid(from) or astar.is_point_solid(to):
		return PackedVector2Array([point])
	var cells: Array[Vector2i] = astar.get_id_path(from, to)
	var path := PackedVector2Array()
	for index: int in range(1, cells.size()):
		path.append(Iso.to_screen(cells[index]))
	return path


func _separation() -> Vector2:
	var push: Vector2 = Vector2.ZERO
	for other: Node in get_tree().get_nodes_in_group(GROUP):
		var enemy: Enemy = other as Enemy
		if enemy == null or enemy == self:
			continue
		var offset: Vector2 = global_position - enemy.global_position
		var dist: float = offset.length()
		if dist > 0.01 and dist < SEPARATION_RADIUS:
			push += offset / dist * (1.0 - dist / SEPARATION_RADIUS)
	return push * (SEPARATION_PUSH / 60.0)


# --- hit reactions and death ---------------------------------------------------


## Hurtbox calls this on the host when a hit connects.
func apply_knockback(impulse: Vector2, stun_seconds: float) -> void:
	var resist: float = clampf(data.knockback_resist if data != null else 0.0, 0.0, 1.0)
	var stun_resist: float = clampf(data.stagger_resist if data != null else 0.0, 0.0, 1.0)
	knockback_velocity = impulse * (1.0 - resist)
	_knockback_decel = knockback_velocity.length() / 0.2 if knockback_velocity.length() > 0.0 else 0.0
	hit_stun_left = stun_seconds * (1.0 - stun_resist)
	if hit_stun_left > 0.0 and machine != null:
		telegraph_progress = -1.0
		machine.change_to(&"HitStun")


func decay_knockback(delta: float) -> void:
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, _knockback_decel * delta)


func _on_damaged(_hit: HitInfo) -> void:
	_flash_left = FLASH_SECONDS


func _on_died(hit: HitInfo) -> void:
	died.emit(hit)
	Events.enemy_killed.emit(self, hit)
	if elite:
		Events.elite_killed.emit(self, hit)
	telegraph_progress = -1.0
	hitbox.active = false
	set_physics_process(false)
	machine.set_physics_process(false)
	await get_tree().create_timer(DEATH_FADE_SECONDS).timeout
	if is_inside_tree():
		queue_free()
