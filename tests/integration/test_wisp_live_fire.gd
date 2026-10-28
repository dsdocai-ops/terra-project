extends GutTest
## Integration: the Lantern Wisp's live fireball flies the real Projectile base
## (W2-A10 on W2-A6). The wisp runs the standard states on the real
## `enemy_base.tscn` — Idle, Chase, Attack through the G3 driver — and the
## Attack state's PROJECTILE branch spawns through the live ProjectileSpawner,
## so the bolt under World/Entities is a `Projectile` armed with the pattern's
## speed and range, on the enemy's team. Single-instance: the offline peer is
## the server, so `spawn()` runs the custom spawn function locally exactly as
## the host does. Owned by enemies-ai.
## Every distance assertion carries a margin, never an exact position: headless
## `move_and_slide` covers ~7.5x velocity * dt (measured in G7a1).
const FRAME := 1.0 / 60.0

const WORLD_SCENE: PackedScene = preload("res://scenes/main/world.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const KIND: StringName = &"lantern_wisp"
## The player waits just inside the fireball's trigger range (220) and inside
## the wisp's hold distance (170), so the wisp opens fire without chasing.
const ROOM_ORIGIN: Vector2 = Vector2(600.0, 600.0)
const PLAYER_OFFSET: Vector2 = Vector2(0.0, -160.0)
## The windup alone is 0.6 s; the poll may wait out a full swing and cooldown.
const POLL_FRAMES: int = 600

var _world: World
var _player: Player
var _wisp: Enemy


func before_each() -> void:
	Enemy.reset_separation_cache()
	_world = WORLD_SCENE.instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world
	NetworkManager.start_solo()
	_player = PLAYER_SCENE.instantiate() as Player
	add_child_autofree(_player)
	NetworkManager.players[NetworkManager.local_peer_id] = _player
	_player.global_position = ROOM_ORIGIN + PLAYER_OFFSET
	var node: Node = _world.enemy_spawner.spawn_enemy(EnemySpawnInfo.new(KIND, ROOM_ORIGIN, false, 0))
	_wisp = node as Enemy


func after_each() -> void:
	NetworkManager.players.erase(NetworkManager.local_peer_id)
	NetworkManager.disconnect_all()
	GameState.world = null
	Enemy.reset_separation_cache()
	_wisp = null


## Waits (real physics frames) until a live projectile is under Entities —
## recording whether the wisp wound up under a telegraph first — or the frame
## budget runs out.
func _wait_for_a_fireball() -> Projectile:
	var saw_telegraph := false
	for _frame: int in POLL_FRAMES:
		await wait_physics_frames(1)
		if _wisp.machine.current_name() == &"Attack" and _wisp.telegraph_progress >= 0.0:
			saw_telegraph = true
		for child: Node in _world.entities.get_children():
			var bolt := child as Projectile
			if bolt != null:
				assert_true(saw_telegraph, "the wisp wound up under a telegraph before the fireball")
				return bolt
	return null


func test_the_wisps_attack_fires_a_real_armed_fireball() -> void:
	assert_eq(_wisp.data.id, KIND, "setup: the wisp carries its data")
	var bolt: Projectile = await _wait_for_a_fireball()
	assert_not_null(bolt, "the wisp's PROJECTILE attack spawned a live fireball")
	if bolt == null:
		return
	assert_same(bolt.get_parent(), _world.entities, "spawned under Entities like any live shot")
	assert_true(bolt.team == Team.Kind.ENEMY, "on the enemy's team")
	assert_true(bolt.hostile, "hostile: the enemy slow/stop stack drags it (TimeManager group)")
	var fireball: AttackPattern = load("res://data/enemies/attacks/wisp_fireball.tres") as AttackPattern
	assert_almost_eq(bolt.flight_velocity().length(), fireball.speed, 0.01,
		"flying at the pattern's projectile speed")
	# The poll sees the bolt one physics frame after `_fire` launched it, so one
	# frame of range (speed / 60) has already burned by the read.
	assert_almost_eq(bolt.range_left(), 420.0, fireball.speed * FRAME + 0.01,
		"armed with the fire range the attack state gives it")
	var to_player: Vector2 = _player.global_position - _wisp.global_position
	assert_gt(bolt.flight_velocity().normalized().dot(to_player.normalized()), 0.9,
		"flying at the player it aimed at (margin, no exact position)")
	assert_true(bolt.template.tags.has(&"enemy"), "carrying the enemy hit template")
