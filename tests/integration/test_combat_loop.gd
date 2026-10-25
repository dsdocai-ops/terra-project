extends GutTest
## The playable loop end to end (W2-A to W3-A, solo): a generated floor paints,
## entering a combat room locks its doors and spawns enemies, the player's
## attacks hurt them, theirs hurt the player, and clearing the room opens the
## doors. Runs against the real world scene on the host.

const WORLD_SCENE: PackedScene = preload("res://scenes/main/world.tscn")
const FORCED_SEED: int = 12

var _world: World = null


func before_each() -> void:
	SpawnDirector.register_populators()
	_world = WORLD_SCENE.instantiate() as World
	add_child_autofree(_world)
	GameState.world = _world
	GameState.forced_seed = FORCED_SEED
	NetworkManager.start_solo()
	GameState.start_run(0, 1, [PlayerSpawnInfo.new(NetworkManager.local_peer_id)])
	await wait_physics_frames(3)


func after_each() -> void:
	GameState.world = null
	GameState.run = null
	GameState.forced_seed = 0
	NetworkManager.disconnect_all()
	FloorGenerator.clear_populators()


func _player() -> Player:
	return NetworkManager.players.get(NetworkManager.local_peer_id) as Player


func _combat_room() -> Room:
	for room: Room in _world.floor_node.rooms:
		if room.type == FloorGenerator.RoomType.COMBAT:
			return room
	return null


func _enemies() -> Array[Enemy]:
	var found: Array[Enemy] = []
	for node: Node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy: Enemy = node as Enemy
		if enemy != null and not enemy.health.is_dead:
			found.append(enemy)
	return found


func _enter(room: Room) -> void:
	var player: Player = _player()
	player.position = room.position
	player.synced_position = room.position
	await wait_physics_frames(4)


func test_the_floor_paints_and_the_player_starts_in_the_start_room() -> void:
	assert_not_null(_world.floor_node, "a floor was built")
	assert_gt(_world.floor_node.rooms.size(), 7)
	var start: Room = _world.floor_node.room_of_type(FloorGenerator.RoomType.START)
	assert_not_null(start)
	assert_eq(_world.floor_node.room_at(_player().position), start, "the player begins in Start")


func test_entering_a_combat_room_locks_the_doors_and_spawns_enemies() -> void:
	var room: Room = _combat_room()
	await _enter(room)
	assert_true(room.triggered, "the room noticed the player")
	assert_gt(_enemies().size(), 1, "enemies spawned")
	var doors: Array = _world.floor_node.doors_by_room[room.spec.index]
	assert_gt(doors.size(), 0)
	for door: Door in doors:
		assert_true(door.closed, "doors are shut")


func test_the_players_attack_damages_an_enemy() -> void:
	var room: Room = _combat_room()
	await _enter(room)
	var enemy: Enemy = _enemies()[0]
	var player: Player = _player()
	enemy.global_position = player.global_position + Vector2(30.0, 0.0)
	enemy.machine.set_physics_process(false)
	var before: int = enemy.health.current_hp
	player.get_node("AttackController").call(&"apply", AttackController.Kind.LIGHT, Vector2.RIGHT, 0.0)
	await wait_physics_frames(20)
	assert_lt(enemy.health.current_hp, before, "the swing landed")


func test_a_crossbow_bolt_damages_an_enemy() -> void:
	var room: Room = _combat_room()
	await _enter(room)
	var enemy: Enemy = _enemies()[0]
	var player: Player = _player()
	enemy.global_position = player.global_position + Vector2(120.0, 0.0)
	enemy.machine.set_physics_process(false)
	var weapons: WeaponController = player.get_node("WeaponController") as WeaponController
	assert_true(weapons.swap(), "swapped to the crossbow")
	var before: int = enemy.health.current_hp
	player.get_node("AttackController").call(&"apply", AttackController.Kind.LIGHT, Vector2.RIGHT, 0.0)
	await wait_physics_frames(40)
	assert_lt(enemy.health.current_hp, before, "the bolt landed")


func test_an_enemy_attack_hurts_the_player() -> void:
	var room: Room = _combat_room()
	await _enter(room)
	var player: Player = _player()
	var health: Health = player.health as Health
	var before: int = health.current_hp
	for enemy: Enemy in _enemies():
		enemy.global_position = player.global_position + Vector2(20.0, 0.0)
	await wait_seconds(3.0)
	assert_lt(health.current_hp, before, "something hit the player")


func test_clearing_the_room_opens_the_doors() -> void:
	var room: Room = _combat_room()
	await _enter(room)
	for enemy: Enemy in _enemies():
		var hit := HitInfo.new()
		hit.final_damage = 9999
		enemy.health.apply_damage(hit)
	await wait_physics_frames(10)
	assert_true(room.cleared, "the room cleared")
	for door: Door in _world.floor_node.doors_by_room[room.spec.index]:
		assert_false(door.closed, "doors open")


func test_dodging_grants_iframes_and_a_cooldown() -> void:
	var player: Player = _player()
	assert_true(player.can_dodge())
	player.get_node("AttackController").call(&"apply", AttackController.Kind.DODGE, Vector2.RIGHT, 0.0)
	await wait_physics_frames(3)
	assert_eq(player.state_machine.current_name(), &"Dodge")
	assert_true(player.hurtbox.invulnerable, "i-frames are up")
	assert_false(player.can_dodge(), "the cooldown runs")
