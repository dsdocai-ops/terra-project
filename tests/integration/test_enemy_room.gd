extends GutTest
## The W2-A9 acceptance room ("Accept: 3 enemies"): three enemies spawned from
## the real `scenes/enemies/enemy_base.tscn` through the live EnemySpawner, in
## one room with a player, each running the G7a1 states (Idle, Chase, Attack,
## HitStun) on the real physics step — the engine ticks the machine, not a
## hand-stepped double. Owned by enemies-ai.
## Single-instance: the offline peer is the server, so spawn() runs the custom
## spawn function locally exactly as the host does.
## Every distance assertion carries a margin, never an exact position: headless
## `move_and_slide` covers ~7.5x velocity * dt (measured in G7a1), so a margin
## is the only honest form here.

const WORLD_SCENE: PackedScene = preload("res://scenes/main/world.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const ENEMY_BASE_PATH: String = "res://scenes/enemies/enemy_base.tscn"
const KIND: StringName = &"hollow_miner"
## The room's floor spot the three spawn around; the player waits just inside
## aggro (280) but well past the swing's trigger range (52).
const ROOM_ORIGIN: Vector2 = Vector2(600.0, 600.0)
const PLAYER_OFFSET: Vector2 = Vector2(0.0, -200.0)
const SPREAD: float = 30.0
const FRAME := 1.0 / 60.0
## One scan finds the player (the Idle scan runs on the first tick), then a
## few frames of closing — generous for the headless overshoot.
const CHASE_FRAMES: int = 12
## The windup alone is 0.55 s; the poll may wait out a full swing and cooldown.
const POLL_FRAMES: int = 600

var _world: World
var _player: Player
var _enemies: Array[Enemy] = []


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
	for index: int in 3:
		var pos: Vector2 = ROOM_ORIGIN + Vector2(float(index) * SPREAD, 0.0)
		var node: Node = _world.enemy_spawner.spawn_enemy(EnemySpawnInfo.new(KIND, pos, false, 0))
		_enemies.append(node as Enemy)


func after_each() -> void:
	NetworkManager.players.erase(NetworkManager.local_peer_id)
	NetworkManager.disconnect_all()
	GameState.world = null
	Enemy.reset_separation_cache()
	_enemies.clear()


## Waits (real physics frames) until `predicate` holds for all three enemies,
## or the frame budget runs out.
func _wait_until_all(predicate: Callable) -> bool:
	var frames: int = 0
	while frames < POLL_FRAMES:
		var all_now: bool = true
		for enemy: Enemy in _enemies:
			if not predicate.call(enemy):
				all_now = false
				break
		if all_now:
			return true
		await wait_physics_frames(1)
		frames += 1
	return false


func test_three_enemies_spawn_from_the_real_base_scene_into_the_room() -> void:
	assert_eq(_world.enemy_spawner.enemy_scene.resource_path, ENEMY_BASE_PATH,
			"the live spawner spawns the real base scene")
	assert_eq(_enemies.size(), 3, "the Accept line's 3 enemies")
	for index: int in 3:
		var enemy: Enemy = _enemies[index]
		assert_not_null(enemy, "enemy %d built" % index)
		assert_eq(enemy.get_parent(), _world.entities, "enemy %d under World/Entities" % index)
		assert_not_null(enemy.data, "enemy %d configured from EnemyData" % index)
		assert_eq(enemy.data.id, KIND, "enemy %d carries the hollow miner data" % index)
		assert_true(enemy.is_in_group(Enemy.GROUP), "enemy %d joined the enemies group" % index)
		assert_eq(enemy.machine.current_name(), &"Idle", "enemy %d starts Idle" % index)


func test_each_enemy_chases_the_player_and_closes_with_margin() -> void:
	var starts: Array[float] = []
	for enemy: Enemy in _enemies:
		starts.append(enemy.global_position.distance_to(_player.global_position))
	await wait_physics_frames(CHASE_FRAMES)
	for index: int in 3:
		var enemy: Enemy = _enemies[index]
		assert_eq(enemy.machine.current_name(), &"Chase", "enemy %d left Idle for Chase on the first scan" % index)
		var now: float = enemy.global_position.distance_to(_player.global_position)
		assert_lt(now, starts[index] - 2.0, "enemy %d closed on the player (margin, no exact position)" % index)
	for first: int in 3:
		for second: int in range(first + 1, 3):
			var apart: float = _enemies[first].global_position.distance_to(_enemies[second].global_position)
			assert_gt(apart, 1.0, "enemies %d and %d do not stack on the shared target" % [first, second])


func test_each_enemy_attacks_through_a_telegraph_when_the_player_is_in_range() -> void:
	_player.global_position = ROOM_ORIGIN + Vector2(SPREAD, -5.0)
	var reached: Array[bool] = [false, false, false]
	var saw_telegraph: Array[bool] = [false, false, false]
	var frames: int = 0
	while frames < POLL_FRAMES and not (reached[0] and reached[1] and reached[2]):
		await wait_physics_frames(1)
		frames += 1
		for index: int in 3:
			var enemy: Enemy = _enemies[index]
			if enemy.machine.current_name() == &"Attack":
				reached[index] = true
				if enemy.telegraph_progress >= 0.0:
					saw_telegraph[index] = true
	for index: int in 3:
		assert_true(reached[index], "enemy %d reached Attack" % index)
		assert_true(saw_telegraph[index], "enemy %d wound up under a telegraph" % index)


func test_each_enemy_takes_a_hit_stun_and_returns_to_chase() -> void:
	var starts: Array[Vector2] = []
	for enemy: Enemy in _enemies:
		starts.append(enemy.global_position)
		enemy.apply_knockback(Vector2(100.0, 0.0), 0.2)
	for index: int in 3:
		assert_eq(_enemies[index].machine.current_name(), &"HitStun", "enemy %d is in HitStun" % index)
	# 0.1 s of frames: mid-stun (the 0.2 s clock is 12 frames), the impulse
	# has already shoved the body — measured with margin, no exact drift.
	await wait_physics_frames(6)
	for index: int in 3:
		var drifted: float = _enemies[index].global_position.distance_to(starts[index])
		assert_gt(drifted, 5.0, "enemy %d drifted with the impulse (margin, no exact drift)" % index)
	# 0.5 s more: the 0.2 s stun clock (plus resist) runs out.
	await wait_physics_frames(30)
	for index: int in 3:
		assert_eq(_enemies[index].machine.current_name(), &"Chase", "enemy %d is back to Chase" % index)
