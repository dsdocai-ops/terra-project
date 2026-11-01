extends GutTest
## Integration of Cave-In, Wren's ultimate (SPEC-abilities "Cave-In", W5-G7): the
## ceiling collapses on every enemy in the caster's room, each enemy takes one
## heavy hit with the stun time set on it, and an enemy in another room is left
## alone. The rooms are real Room nodes that hold the caster in players_inside, the
## enemies are the real enemy scene with their room set, and the cast is the real
## scene. Owned by abilities. Sync: host only; the test runs as the host offline.

const DATA_PATH: String = "res://data/abilities/ultimates/cave_in.tres"
const ENEMY_SCENE: String = "res://scenes/enemies/enemy_base.tscn"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const ENEMY_KIND: StringName = &"hollow_miner"
const ROOM_ENEMY_COUNT: int = 3

var _data: AbilityData
var _player: Player
var _room: Room
var _other_room: Room


func before_each() -> void:
	_data = load(DATA_PATH) as AbilityData
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_room = _make_room()
	_room.players_inside.append(_player)
	_other_room = _make_room()


## A real Room with its physics off, so no scan runs during the test.
func _make_room() -> Room:
	var room := Room.new()
	add_child_autofree(room)
	room.set_physics_process(false)
	return room


## A real enemy from the enemy scene, placed in `room`.
func _make_enemy(room: Room) -> Enemy:
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	add_child_autofree(enemy)
	assert_true(enemy.setup(ENEMY_KIND), "the enemy scene sets up as %s" % ENEMY_KIND)
	enemy.room = room
	return enemy


func _cast() -> CaveInCast:
	var cast := _data.cast_scene.instantiate() as CaveInCast
	cast.setup(_player, _data, 1, _player.global_position, Vector2.RIGHT)
	add_child_autofree(cast)
	return cast


## The enemy each recorded hit landed on, in the order the hits landed.
func _hit_targets() -> Array[Node]:
	var targets: Array[Node] = []
	for index: int in get_signal_emit_count(Events, "hit_landed"):
		var params: Array = get_signal_parameters(Events, "hit_landed", index)
		var hit := params[0] as HitInfo
		if hit != null:
			targets.append(hit.target)
	return targets


func test_cave_in_is_an_ultimate_with_a_cooldown_three_ranks_and_a_cast_scene() -> void:
	assert_not_null(_data, "cave_in.tres loads from the ultimates folder")
	if _data == null:
		return
	assert_true(_data.is_ultimate, "Cave-In is marked as an ultimate")
	assert_gt(_data.cooldown, 0.0, "Cave-In has a short lockout")
	assert_eq(_data.ranks.size(), AbilityData.MAX_RANK, "Cave-In has three ranks")
	assert_not_null(_data.cast_scene, "Cave-In names its cast scene")


func test_every_enemy_in_the_room_is_hit_once() -> void:
	var enemies: Array[Enemy] = []
	for index: int in ROOM_ENEMY_COUNT:
		enemies.append(_make_enemy(_room))
	watch_signals(Events)
	_cast()
	var targets := _hit_targets()
	assert_eq(targets.size(), ROOM_ENEMY_COUNT, "one hit lands per enemy in the room")
	for enemy: Enemy in enemies:
		assert_eq(targets.count(enemy), 1, "%s is hit exactly once" % enemy.name)
	for index: int in get_signal_emit_count(Events, "hit_landed"):
		var hit := get_signal_parameters(Events, "hit_landed", index)[0] as HitInfo
		assert_eq(hit.hit_stun_seconds, _data.rank_data(1).extra, "the hit on %s carries the stun time" % hit.target.name)


func test_each_room_hit_is_heavy_and_carries_the_stun_time_of_rank_one() -> void:
	_make_enemy(_room)
	watch_signals(Events)
	_cast()
	assert_eq(get_signal_emit_count(Events, "hit_landed"), 1, "the one enemy is hit")
	if get_signal_emit_count(Events, "hit_landed") < 1:
		return
	var hit := get_signal_parameters(Events, "hit_landed", 0)[0] as HitInfo
	assert_true(hit.is_heavy, "the Cave-In hit is heavy")
	assert_eq(hit.hit_stun_seconds, _data.rank_data(1).extra, "the stun time is the rank's extra")
	assert_gt(hit.hit_stun_seconds, 0.0, "the stun is a positive time")
	assert_eq(hit.base_damage, _data.base_damage * _data.rank_data(1).damage_mult, "the hit carries the ability's damage at rank 1")


func test_an_enemy_in_another_room_is_not_hit() -> void:
	_make_enemy(_room)
	var outside := _make_enemy(_other_room)
	watch_signals(Events)
	_cast()
	assert_false(_hit_targets().has(outside), "an enemy in another room takes no hit")
	assert_eq(get_signal_emit_count(Events, "hit_landed"), 1, "only the room's enemy is hit")


func test_a_cast_with_no_caster_hits_nothing() -> void:
	_make_enemy(_room)
	watch_signals(Events)
	var cast := _data.cast_scene.instantiate() as CaveInCast
	cast.setup(null, _data, 1, Vector2.ZERO, Vector2.RIGHT)
	add_child_autofree(cast)
	assert_eq(get_signal_emit_count(Events, "hit_landed"), 0, "with no caster there is no room, so no hit")
