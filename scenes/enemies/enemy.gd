class_name Enemy
extends CharacterBody2D
## The one enemy scene every enemy type is built on (SPEC-enemies-ai
## `enemy_base`): configured entirely from `EnemyData`, driven by a small
## StateMachine (Idle, Chase, Attack, HitStun, Stagger) whose decisions live in
## the pure `EnemyStateLogic` and `Targeting`, with the routing on the floor's
## `AStarGrid2D` in the pure `EnemyPathing`. Owned by enemies-ai.
## Sync: the host runs AI, attacks, HP and death; StateSync replicates
## position, animation tag, current HP, the telegraph progress and aim, and the
## spawn-time `kind`/`elite`. Clients only present that state. Art: the
## `EnemyData.sprite_frames` sheet, facing picked locally from movement (or the
## replicated aim while standing); a coloured body polygon when there is none.

signal died(hit: HitInfo)

const SEPARATION_RADIUS: float = 22.0
const SEPARATION_PUSH: float = 40.0
const PATH_REFRESH_SECONDS: float = 0.5
const DEATH_FADE_SECONDS: float = 0.6
const GROUP: StringName = &"enemies"
## Stand-in for an unknown kind (debug `spawn grub`).
const FALLBACK_KIND: StringName = &"hollow_miner"
## Poise refills at this share of its maximum per second, starting this long
## after the last hit (combat v2).
const POISE_REFILL_DELAY_SECONDS: float = 1.5
const POISE_REFILL_PER_SECOND: float = 0.5

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
## Poise pool (host only, never replicated): drained by `HitInfo.poise_damage`,
## broken at 0. `poise_max` 0 means fodder that staggers on every hit.
var poise: float = 0.0
var poise_max: float = 0.0
## True while in the Stagger state. Replicated by StateSync so every peer can
## show the dazed marker; set and cleared by the Stagger state on the host.
var staggered: bool = false:
	set(value):
		staggered = value
		queue_redraw()

var _path: PackedVector2Array = PackedVector2Array()
var _path_timer: float = 0.0
var _knockback_decel: float = 0.0
var _seconds_since_hit: float = POISE_REFILL_DELAY_SECONDS
var _facing: int = 0
var _last_position: Vector2 = Vector2.ZERO
## Height of one sprite frame, 0 while the placeholder polygon is shown.
var _sprite_height: float = 0.0

## The per-frame shared separation hash: the first `_separation` this physics
## frame collects the whole group (self included, by instance id) into it,
## every push this frame then reads only its own nine cells — never a
## group-wide scan. It is a snapshot: a body that moved earlier in the frame
## (the flinch shove's `move_and_slide` runs before a state's `_separation`)
## is read at its snapshot position, up to one frame stale — the old live
## group scan read positions as they were. The query's own entry is dropped
## by id at the lookup, so a stale self never pushes the body along its own
## shove. Host-only AI over plain positions, nothing to sync.
static var _frame_hash: EnemySeparation = null
static var _hash_frame: int = -1
static var _hash_group_size: int = -1

@onready var stat_block: StatBlock = $StatBlock
@onready var health: Health = $Health
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var machine: StateMachine = $StateMachine
@onready var telegraph: Telegraph = $Telegraph
@onready var body: Polygon2D = $Body
@onready var sprite: AnimatedSprite2D = $Sprite
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
		push_warning("[enemy] no EnemyData for '%s'; using %s" % [kind, FALLBACK_KIND])
		data = EnemyData.find(FALLBACK_KIND)
	if data == null:
		return false
	var stats: StatBlock = get_node("StatBlock") as StatBlock
	stats.base = data.base_stats.duplicate()
	var biome: int = GameState.run.biome_index if GameState.run != null else maxi(GameState.remote_floor_index - 1, 0) / BiomeData.FLOORS_PER_BIOME + 1
	var max_hp: float = float(stats.base.get(StatBlock.Stat.MAX_HP, 20.0))
	if data.scales_hp:
		max_hp = Scaling.enemy_max_hp(max_hp, biome)
	if elite:
		max_hp = Scaling.elite_hp(max_hp)
	stats.base[StatBlock.Stat.MAX_HP] = max_hp
	poise_max = maxf(data.poise, 0.0)
	poise = poise_max
	var poly: Polygon2D = get_node("Body") as Polygon2D
	var r: float = data.radius * (1.3 if elite else 1.0)
	poly.polygon = PackedVector2Array([Vector2(-r, -r * 1.6), Vector2(r, -r * 1.6), Vector2(r, r * 0.5), Vector2(-r, r * 0.5)])
	poly.color = data.color.lightened(0.25) if elite else data.color
	_apply_sprite(poly)
	(get_node("BodyShape") as CollisionShape2D).shape = _circle(r)
	(get_node("Hurtbox/HurtShape") as CollisionShape2D).shape = _circle(r + 2.0)
	return true


## Swaps the placeholder polygon for the data's sprite sheet when it has one.
## Feet sit 4 px above the frame's bottom edge (gen_sprites_v2.py), so the
## sprite is raised by half a frame less those 4 px.
func _apply_sprite(poly: Polygon2D) -> void:
	var spr: AnimatedSprite2D = get_node("Sprite") as AnimatedSprite2D
	if data.sprite_frames == null or not data.sprite_frames.has_animation(&"idle_s"):
		spr.visible = false
		poly.visible = true
		_sprite_height = 0.0
		return
	spr.sprite_frames = data.sprite_frames
	var first: Texture2D = data.sprite_frames.get_frame_texture(&"idle_s", 0)
	_sprite_height = float(first.get_height()) if first != null else 0.0
	spr.position = Vector2(0.0, -(_sprite_height * 0.5 - 4.0))
	spr.modulate = Color(1.2, 1.1, 0.85, 1.0) if elite else Color.WHITE
	spr.visible = true
	poly.visible = false
	spr.play(&"idle_s")


## Picks the facing from this frame's movement (the replicated aim while
## standing still) and plays walk or idle for it. Presentation only: every
## peer runs it on its own copy of the position.
func _animate_sprite() -> void:
	var motion: Vector2 = global_position - _last_position
	_last_position = global_position
	var moving: bool = motion.length() > 0.2 or current_anim == &"walk"
	var dir: Vector2 = motion if motion.length() > 0.2 else aim_dir
	_facing = Facing.index_for(dir, _facing, 15.0)
	var anim := StringName("%s_%s" % ["walk" if moving else "idle", Facing.suffix(_facing)])
	if sprite.animation != anim and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)


func _circle(radius: float) -> CircleShape2D:
	var shape := CircleShape2D.new()
	shape.radius = radius
	return shape


func _ready() -> void:
	add_to_group(GROUP)
	synced_position = global_position
	_last_position = global_position
	hurtbox.team = Team.Kind.ENEMY
	hitbox.team = Team.Kind.ENEMY
	HitFlash.attach(self, [body, sprite])
	machine.set_physics_process(multiplayer.is_server())
	if multiplayer.is_server():
		health.died.connect(_on_died)
		health.damaged.connect(_on_damaged)
		if room != null:
			room.track_enemy(self)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var scaled: float = delta * _time_scale()
	attack_cooldown_left = maxf(attack_cooldown_left - scaled, 0.0)
	_path_timer = maxf(_path_timer - scaled, 0.0)
	_refill_poise(scaled)
	_shove(scaled)


func _process(delta: float) -> void:
	if staggered:
		queue_redraw()
	if sprite.visible:
		_animate_sprite()
	telegraph.progress = telegraph_progress
	telegraph.direction = aim_dir
	if multiplayer.is_server():
		synced_position = global_position
	else:
		global_position = global_position.lerp(synced_position, clampf(delta * 15.0, 0.0, 1.0))


## Debug and smoke hook: a flat hit that bypasses damage maths. Host only.
func apply_hit(amount: int) -> bool:
	if not multiplayer.is_server() or health.is_dead:
		return false
	var flat := HitInfo.new()
	flat.final_damage = amount
	return health.apply_damage(flat)


## Current HP, under the name the debug console and smoke driver read.
var current_hp: int:
	get:
		return health.current_hp if health != null else 0

## A thin HP bar over a hurt enemy (placeholder; the real one arrives with the
## HUD pass). Drawn locally from the replicated Health.
func _draw() -> void:
	if staggered and data != null:
		_draw_stagger_marker()
	if health == null or data == null or health.max_hp <= 0 or health.current_hp >= health.max_hp or health.is_dead:
		return
	var width: float = data.radius * 2.6
	var top: float = -data.radius * 2.0 - 4.0
	if _sprite_height > 0.0:
		top = -(_sprite_height - 4.0) - 6.0
	var fraction: float = clampf(float(health.current_hp) / float(health.max_hp), 0.0, 1.0)
	draw_rect(Rect2(-width * 0.5 - 1.0, top - 1.0, width + 2.0, 5.0), Color(0.05, 0.03, 0.02, 0.9))
	draw_rect(Rect2(-width * 0.5, top, width * fraction, 3.0), Color(0.85, 0.25, 0.2, 1.0) if not elite else Color(0.95, 0.7, 0.2, 1.0))

# --- targeting and movement ----------------------------------------------------


## The target to chase (SPEC-enemies-ai "Targeting"): the pure `Targeting.pick`
## over the players — a taunt overrides the distance, an `untargetable` player
## is invisible (aggro drops when that leaves nothing), the spread joins the
## player the pack is not focused on, and the current target is kept while it
## stays near the nearest. Null when nothing is targetable. Host only.
func pick_target() -> Node2D:
	var candidates: Array[Targeting.Candidate] = []
	for player: Player in NetworkManager.players.values():
		if is_instance_valid(player):
			candidates.append(Targeting.candidate(player))
	_count_targeters(candidates)
	var picked := Targeting.pick(global_position, target, candidates)
	return picked.node if picked != null else null


## The spread's load: how many enemies of the pack currently hold each
## candidate, so a fresh pick joins the player the pack is not already focused
## on. This enemy's own hold does not count — it is the hysteresis, not load.
## Host only.
func _count_targeters(candidates: Array[Targeting.Candidate]) -> void:
	for c: Targeting.Candidate in candidates:
		c.targeters = 0
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy == self or not is_instance_valid(enemy.target):
			continue
		for c: Targeting.Candidate in candidates:
			if c.node == enemy.target:
				c.targeters += 1


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


## TimeManager's multiplier for this enemy: slows, time stops and hit-stop.
func _time_scale() -> float:
	return TimeManager.scale_for(self)


## The wiring around the pure `EnemyPathing`: rebuilds the route on
## `PATH_REFRESH_SECONDS`, trims the waypoints this body reached and steers at
## the next one (direct at `point` when there is no floor to path on).
func _next_waypoint(point: Vector2) -> Vector2:
	var world: World = GameState.world
	if world == null or world.floor_node == null or world.floor_node.astar == null:
		return point
	if _path_timer <= 0.0 or _path.is_empty():
		_path_timer = PATH_REFRESH_SECONDS
		_path = EnemyPathing.build_path(world.floor_node.astar, global_position, point)
	_path = EnemyPathing.advance(_path, global_position, EnemyPathing.ARRIVAL_RADIUS)
	return EnemyPathing.goal(_path, point)


## Drops the shared separation hash so the next `_separation` rebuilds it.
## The frame and group-size checks below already catch the game's drift; tests
## (which can sit on one physics frame for many bodies) call this between
## setups, and a caller that spawned or freed enemies off the physics step can too.
static func reset_separation_cache() -> void:
	_frame_hash = null
	_hash_frame = -1
	_hash_group_size = -1


## The separation push, through the pure `EnemySeparation` spatial hash (see
## the `_frame_hash` note by the member block for the sharing).
func _separation() -> Vector2:
	var frame: int = Engine.get_physics_frames()
	var group_size: int = get_tree().get_nodes_in_group(GROUP).size()
	if _frame_hash == null or _hash_frame != frame or _hash_group_size != group_size:
		_hash_frame = frame
		_hash_group_size = group_size
		_frame_hash = EnemySeparation.new(SEPARATION_RADIUS)
		for node: Node in get_tree().get_nodes_in_group(GROUP):
			var enemy := node as Enemy
			if enemy != null:
				_frame_hash.insert(enemy.global_position, enemy.get_instance_id())
	return EnemySeparation.push_for(global_position, _frame_hash.nearby(global_position, get_instance_id()), SEPARATION_RADIUS, SEPARATION_PUSH)


# --- hit reactions and death ---------------------------------------------------


## Hurtbox calls this on the host before `hit_landed` fires: drains poise by the
## hit's poise damage (scaled by `stagger_resist`) and marks `hit.staggered`
## when it broke. A 0-poise enemy staggers on every hit that carries poise
## damage. A hit on an already staggered enemy drains nothing and does not
## stagger it again, so stagger can not be chained forever.
func absorb_hit_poise(hit: HitInfo) -> void:
	_seconds_since_hit = 0.0
	if staggered:
		return
	var resist: float = clampf(data.stagger_resist if data != null else 0.0, 0.0, 1.0)
	var drain: float = hit.poise_damage * (1.0 - resist)
	if drain <= 0.0:
		return
	if poise_max <= 0.0:
		hit.staggered = true
		return
	poise = maxf(poise - drain, 0.0)
	hit.staggered = poise <= 0.0


## Hurtbox calls this on the host when a hit connects, after `absorb_hit_poise`.
## With the hit: a broken poise enters Stagger (cancelling the attack and its
## telegraph); otherwise it is a flinch, a knockback shove with no state change,
## so a windup keeps winding up. Without a hit (the older two-argument callers)
## it is the old full stun.
func apply_knockback(impulse: Vector2, stun_seconds: float, hit: HitInfo = null) -> void:
	var resist: float = clampf(data.knockback_resist if data != null else 0.0, 0.0, 1.0)
	knockback_velocity = impulse * (1.0 - resist)
	_knockback_decel = EnemyStateLogic.knockback_decel(knockback_velocity.length())
	if hit == null:
		var stun_resist: float = clampf(data.stagger_resist if data != null else 0.0, 0.0, 1.0)
		hit_stun_left = stun_seconds * (1.0 - stun_resist)
		if hit_stun_left > 0.0 and machine != null:
			telegraph_progress = -1.0
			machine.change_to(&"HitStun")
		return
	if hit.staggered:
		enter_stagger(hit)


## Cancels whatever the enemy was doing and enters Stagger; announces it.
func enter_stagger(hit: HitInfo) -> void:
	telegraph_progress = -1.0
	hitbox.active = false
	if machine != null and machine.change_to(&"Stagger"):
		Events.enemy_staggered.emit(self, hit)


## Back to a full pool; the Stagger state calls this on the way out.
func refill_poise() -> void:
	poise = poise_max
	_seconds_since_hit = 0.0


## After a quiet spell the pool refills at half its size per second, in
## TimeManager-scaled time so a time stop holds it too. Not while staggered.
func _refill_poise(scaled_delta: float) -> void:
	if poise_max <= 0.0 or staggered or poise >= poise_max:
		return
	_seconds_since_hit += scaled_delta
	if _seconds_since_hit >= POISE_REFILL_DELAY_SECONDS:
		poise = minf(poise + poise_max * POISE_REFILL_PER_SECOND * scaled_delta, poise_max)


## A flinch moves the enemy without changing its state, at TimeManager's scale
## for this enemy so a time stop or hit-stop holds the shove too (the decay
## above already runs on the scaled delta). HitStun and Stagger move themselves
## from the same impulse.
func _shove(scaled_delta: float) -> void:
	if knockback_velocity.is_zero_approx() or machine == null:
		return
	var current: StringName = machine.current_name()
	if current == &"HitStun" or current == &"Stagger":
		return
	decay_knockback(scaled_delta)
	velocity = knockback_velocity * _time_scale()
	move_and_slide()
	if is_on_wall():
		knockback_velocity = Vector2.ZERO


func decay_knockback(delta: float) -> void:
	knockback_velocity = EnemyStateLogic.decayed_knockback(knockback_velocity, _knockback_decel, delta)


func _on_damaged(_hit: HitInfo) -> void:
	queue_redraw()


func _on_died(hit: HitInfo) -> void:
	died.emit(hit)
	Events.enemy_killed.emit(self, hit)
	if elite:
		Events.elite_killed.emit(self, hit)
	telegraph_progress = -1.0
	hitbox.active = false
	set_physics_process(false)
	machine.set_physics_process(false)
	create_tween().tween_property(body, "modulate:a", 0.0, DEATH_FADE_SECONDS)
	hurtbox.set_deferred(&"monitorable", false)
	await get_tree().create_timer(DEATH_FADE_SECONDS).timeout
	if is_inside_tree():
		queue_free()


## Three gold dots circling above the head while staggered (placeholder art).
func _draw_stagger_marker() -> void:
	var top: float = -data.radius * 2.0 - 14.0
	if _sprite_height > 0.0:
		top = -(_sprite_height - 4.0) - 14.0
	var phase: float = float(Time.get_ticks_msec()) / 220.0
	for index: int in 3:
		var angle: float = phase + TAU * float(index) / 3.0
		draw_circle(Vector2(cos(angle) * 9.0, top + sin(angle) * 3.0), 2.0, Color(1.0, 0.85, 0.2, 1.0))
