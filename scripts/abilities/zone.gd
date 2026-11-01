class_name Zone
extends Area2D
## An area that ticks a hit onto every opposing Hurtbox it overlaps, every
## `tick_interval`, for `duration` seconds (SPEC-abilities "Zone"). Owned by
## abilities. Sync: host only. The host runs the ticks and the hits; Hurtbox.receive
## early-returns on clients, so a client's copy only shows the area. Both the
## clock and the tick interval run in TimeManager-scaled time of `time_node`, so a
## slowed owner's zone slows with them.
##
## The hit template is copied for every target, so the template is never mutated.
## Overlaps are read from the physics server, so a tick needs the zone in the
## tree with its monitoring on (the default).

const BODY_LAYERS: int = Hitbox.LAYER_ENEMY_BODY | Hitbox.LAYER_PLAYER_BODY
const MIN_TICK_INTERVAL: float = 0.01
const MIN_RADIUS: float = 1.0
const SHAPE_NODE: String = "Shape"

## The side the zone hurts from. Hits on the other side of this are struck.
var team: Team.Kind = Team.Kind.PLAYER
## Ticks that ran so far, hit or not.
var ticks_done: int = 0
## Barrier Dome's mode: every step the zone ends the enemy projectiles inside its
## edge (block_projectiles), and it does not need a template to do so. Host only.
var blocks_projectiles: bool = false

var _template: HitInfo = null
var _duration: float = 0.0
var _tick_interval: float = 0.0
var _time_node: Node = null
var _left: float = 0.0
var _until_tick: float = 0.0
var _radius: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = BODY_LAYERS
	monitoring = true
	monitorable = false


## Sets the template, the length, the tick interval and the node whose time
## scale runs the zone. Call before the zone enters the tree, or right after.
func configure(template: HitInfo, seconds: float, interval: float, time_node: Node) -> void:
	_template = template
	_duration = maxf(seconds, 0.0)
	_tick_interval = maxf(interval, MIN_TICK_INTERVAL)
	_time_node = time_node
	_left = _duration
	_until_tick = _tick_interval


## Gives the zone a circular area `radius` pixels across, so it can overlap
## hurtboxes. A zone with no shape overlaps nothing. Call before the zone enters
## the tree.
func set_radius(radius: float) -> void:
	var shape_node := get_node_or_null(SHAPE_NODE) as CollisionShape2D
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = SHAPE_NODE
		add_child(shape_node)
	var circle := CircleShape2D.new()
	circle.radius = maxf(radius, MIN_RADIUS)
	shape_node.shape = circle
	_radius = circle.radius


func _physics_process(delta: float) -> void:
	advance(delta)


## Runs the zone's clock for `delta` seconds of TimeManager-scaled time: every
## tick that is due runs on the host, a blocking zone ends the enemy bolts in its
## edge, and the zone frees itself when its duration is spent. Public so tests can
## run it without physics frames.
func advance(delta: float) -> void:
	var scaled: float = delta * TimeManager.scale_for(_scaled_node())
	_left -= scaled
	if multiplayer.is_server():
		_until_tick -= scaled
		while _until_tick <= 0.0:
			_tick()
			_until_tick += _tick_interval
		if blocks_projectiles:
			block_projectiles()
	if _left <= 0.0:
		queue_free()


## Ends every enemy Projectile inside the zone's edge, as a wall would (Barrier
## Dome). The bolts are found with a physics shape query on the enemy hitbox layer,
## which finds a bolt wherever it sits in the circle, so a bolt cannot cross the
## edge unseen. Allied bolts are left flying. Host only: advance calls it only on
## the host.
func block_projectiles() -> void:
	if _radius <= 0.0 or not is_inside_tree():
		return
	var shape := CircleShape2D.new()
	shape.radius = _radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, global_position)
	query.collision_mask = Hitbox.LAYER_HITBOX_ENEMY
	query.collide_with_bodies = false
	query.collide_with_areas = true
	for found: Dictionary in get_world_2d().direct_space_state.intersect_shape(query):
		var bolt := found["collider"] as Projectile
		# The distance check reads the bolt where it is, not where the physics server
		# last synced it, so a bolt just placed or moved is judged on its real position.
		if bolt != null and bolt.team == Team.Kind.ENEMY and bolt.global_position.distance_to(global_position) <= _radius:
			bolt.block()


## One hit onto one hurtbox: a copy of the template, unless the hurtbox is on the
## zone's own side or the zone has no template. Returns true when the hurtbox
## took the hit. Host only; a client never strikes.
func strike(hurtbox: Hurtbox) -> bool:
	if hurtbox == null or _template == null or not multiplayer.is_server():
		return false
	if not Team.opposes(team, hurtbox.team):
		return false
	return hurtbox.receive(_template.copy())


func _tick() -> void:
	ticks_done += 1
	for area: Area2D in get_overlapping_areas():
		var hurtbox := area as Hurtbox
		if hurtbox != null:
			strike(hurtbox)


## The node whose TimeManager scale runs the zone, or this zone when none was set.
func _scaled_node() -> Node:
	if _time_node != null:
		return _time_node
	return self
