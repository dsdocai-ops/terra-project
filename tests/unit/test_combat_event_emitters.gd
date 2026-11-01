extends GutTest
## Production emitters for the combat-side `Events` signals (W4-A4): each one is
## fired by its real owning code path and not through `tests/helpers/
## event_emitter.gd`. Covers `weapon_swapped` (WeaponController), `enemy_spawned`
## (SpawnDirector.spawn_one), and `enemy_killed` (Enemy's death path). The other
## emitters already have real-path tests: `hit_landed`, `crit_landed`,
## `player_damaged` (test_hurtbox), `heavy_attack_released` (test_attack_controller),
## `player_dodged` (test_dodge_state), `projectile_fired` (test_crossbow_live_fire).
## Owned by combat-core. Host-side: the offline peer is the server, so the spawn
## and the death run exactly as the host's do. Listeners are named methods, never
## lambdas (LESSONS: `.connect(lambda)` never fires under GUT).

const WORLD_SCENE_PATH: String = "res://scenes/main/world.tscn"
const PLAYER_SCENE_PATH: String = "res://scenes/player/player.tscn"
const CROSSBOW_PATH: String = "res://data/weapons/crossbow.tres"
const PICKAXE_PATH: String = "res://data/weapons/pickaxe.tres"
const KIND: StringName = &"hollow_miner"

var _world: World = null
var _player: Player = null
var _swaps: Array[int] = []
var _swapped_players: Array[Player] = []
var _spawned: Array[Node] = []
var _killed: Array[Node] = []
var _killed_hits: Array[HitInfo] = []


func before_each() -> void:
	_swaps.clear()
	_swapped_players.clear()
	_spawned.clear()
	_killed.clear()
	_killed_hits.clear()
	Events.weapon_swapped.connect(_on_weapon_swapped)
	Events.enemy_spawned.connect(_on_enemy_spawned)
	Events.enemy_killed.connect(_on_enemy_killed)


func after_each() -> void:
	if Events.weapon_swapped.is_connected(_on_weapon_swapped):
		Events.weapon_swapped.disconnect(_on_weapon_swapped)
	if Events.enemy_spawned.is_connected(_on_enemy_spawned):
		Events.enemy_spawned.disconnect(_on_enemy_spawned)
	if Events.enemy_killed.is_connected(_on_enemy_killed):
		Events.enemy_killed.disconnect(_on_enemy_killed)
	NetworkManager.players.erase(1)
	GameState.world = null
	_world = null
	_player = null
	Enemy.reset_separation_cache()


func _on_weapon_swapped(player: Player, slot: int) -> void:
	_swapped_players.append(player)
	_swaps.append(slot)


func _on_enemy_spawned(enemy: Node) -> void:
	_spawned.append(enemy)


func _on_enemy_killed(enemy: Node, hit: HitInfo) -> void:
	_killed.append(enemy)
	_killed_hits.append(hit)


func _wire_world() -> void:
	_world = (load(WORLD_SCENE_PATH) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world


func _add_player() -> Player:
	_player = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.position = Vector2.ZERO
	NetworkManager.players[1] = _player
	return _player


# --- weapon_swapped ----------------------------------------------------------------

func test_a_real_swap_emits_weapon_swapped_with_the_player_and_the_new_slot() -> void:
	var player: Player = _add_player()
	var weapons := player.get_node("WeaponController") as WeaponController
	weapons.equip(1, load(CROSSBOW_PATH) as WeaponData)
	assert_true(weapons.swap(), "the swap goes through")
	assert_eq(_swaps, [1] as Array[int], "weapon_swapped fired once with slot 1")
	assert_eq(_swapped_players, [player] as Array[Player], "and carried the swapping player")


func test_a_refused_swap_inside_the_lockout_emits_nothing() -> void:
	var player: Player = _add_player()
	var weapons := player.get_node("WeaponController") as WeaponController
	assert_true(weapons.swap())
	assert_false(weapons.swap(), "a swap inside the lockout is refused")
	assert_eq(_swaps.size(), 1, "only the accepted swap emits")


func test_selecting_the_live_slot_emits_nothing() -> void:
	var player: Player = _add_player()
	var weapons := player.get_node("WeaponController") as WeaponController
	assert_false(weapons.select_slot(weapons.active_slot), "the live slot is a no-op")
	assert_eq(_swaps.size(), 0, "no weapon_swapped for a no-op")


# --- enemy_spawned -----------------------------------------------------------------

func test_spawn_one_emits_enemy_spawned_with_the_new_enemy() -> void:
	_wire_world()
	var enemy: Enemy = SpawnDirector.spawn_one(KIND, Vector2(400, 0))
	assert_not_null(enemy, "the host spawns the enemy")
	assert_eq(_spawned, [enemy] as Array[Node], "enemy_spawned fired once with that enemy")


func test_a_client_spawn_attempt_emits_no_enemy_spawned() -> void:
	# spawn_one is host-only: with no world wired it returns null and must not emit.
	GameState.world = null
	var enemy: Enemy = SpawnDirector.spawn_one(KIND, Vector2(400, 0))
	assert_null(enemy, "no world, no spawn")
	assert_eq(_spawned.size(), 0, "no enemy_spawned without a spawn")


# --- enemy_killed ------------------------------------------------------------------

func test_a_lethal_hit_emits_enemy_killed_once_with_the_enemy_and_the_hit() -> void:
	_wire_world()
	var enemy: Enemy = SpawnDirector.spawn_one(KIND, Vector2(400, 0))
	var hit := HitInfo.new()
	hit.final_damage = 100000
	enemy.health.apply_damage(hit)
	assert_eq(_killed, [enemy] as Array[Node], "enemy_killed fired once for that enemy")
	assert_eq(_killed_hits, [hit] as Array[HitInfo], "and carried the killing hit")


func test_a_non_lethal_hit_emits_no_enemy_killed() -> void:
	_wire_world()
	var enemy: Enemy = SpawnDirector.spawn_one(KIND, Vector2(400, 0))
	var hit := HitInfo.new()
	hit.final_damage = 1
	enemy.health.apply_damage(hit)
	assert_eq(_killed.size(), 0, "a survivor is not a kill")
