extends GutTest
## The six elite affixes (SPEC-enemies-ai "Elites", W4-A1 part 2): one behaviour
## test per affix, run on the real enemy scene. Each behaviour runs on the host
## only: Enemy calls it from its server-only physics, damage and death paths.
## Owned by enemies-ai. Sync: SPLITTING copies replicate through the room's spawn
## (SpawnDirector.spawn_one), the others change host state that StateSync carries.

const ENEMY_SCENE := "res://scenes/enemies/enemy_base.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const WORLD_SCENE_PATH: String = "res://scenes/main/world.tscn"
const ELITE_KIND: StringName = &"hollow_miner"

var _world: World = null


func before_each() -> void:
	_world = null


func after_each() -> void:
	GameState.world = null
	_world = null


func _spawn(affix: EliteAffix.Affix) -> Enemy:
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	assert_true(enemy.setup(ELITE_KIND, true, affix), "the elite data loads")
	add_child_autofree(enemy)
	enemy.set_physics_process(false)
	return enemy


func _light_hit() -> HitInfo:
	var hit := HitInfo.new()
	hit.base_damage = 5.0
	return hit


func _heavy_hit() -> HitInfo:
	var hit := _light_hit()
	hit.is_heavy = true
	return hit


func _wire_world() -> void:
	_world = (load(WORLD_SCENE_PATH) as PackedScene).instantiate() as World
	_world.debug_test_floor = false
	add_child_autofree(_world)
	GameState.world = _world


func _player_at(pos: Vector2) -> Player:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(player)
	player.global_position = pos
	player.add_to_group(&"player")
	return player


# --- the table -----------------------------------------------------------------

func test_every_affix_but_none_has_a_behaviour_script() -> void:
	for affix: int in EliteAffix.Affix.values():
		var script := EliteAffix.behavior_script(affix as EliteAffix.Affix)
		if affix == EliteAffix.Affix.NONE:
			assert_null(script, "NONE has no behaviour")
		else:
			assert_not_null(script, "affix %d has a behaviour script" % affix)


func test_the_affix_node_is_attached_only_to_an_affixed_elite() -> void:
	var enemy := _spawn(EliteAffix.Affix.HASTED)
	assert_not_null(enemy.affix_behavior, "an affixed elite runs its behaviour")
	var plain := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	plain.setup(ELITE_KIND, false, EliteAffix.Affix.HASTED)
	add_child_autofree(plain)
	assert_null(plain.affix_behavior, "a plain enemy has no behaviour node")


# --- SHIELDED ------------------------------------------------------------------

func test_shielded_absorbs_three_light_hits_and_the_fourth_lands() -> void:
	var enemy := _spawn(EliteAffix.Affix.SHIELDED)
	var shield := enemy.affix_behavior as AffixShielded
	for index: int in AffixShielded.SHIELD_MAX_HITS:
		assert_true(enemy.absorbs_hit(_light_hit()), "hit %d is absorbed" % (index + 1))
	assert_false(shield.is_up(), "the third absorbed hit breaks it")
	assert_false(enemy.absorbs_hit(_light_hit()), "with the shield down, the next hit lands")


func test_shielded_heavy_breaks_the_shield_and_lands() -> void:
	var enemy := _spawn(EliteAffix.Affix.SHIELDED)
	var shield := enemy.affix_behavior as AffixShielded
	assert_false(enemy.absorbs_hit(_heavy_hit()), "a heavy is not absorbed")
	assert_false(shield.is_up(), "a heavy breaks the shield")


func test_shielded_recharges_after_its_recharge_time() -> void:
	var enemy := _spawn(EliteAffix.Affix.SHIELDED)
	var shield := enemy.affix_behavior as AffixShielded
	enemy.absorbs_hit(_heavy_hit())
	shield.process(AffixShielded.SHIELD_RECHARGE_SECONDS - 0.1, enemy)
	assert_false(shield.is_up(), "still down just before the recharge")
	shield.process(0.2, enemy)
	assert_true(shield.is_up(), "back up after the recharge time")
	assert_eq(shield.hits_left, AffixShielded.SHIELD_MAX_HITS, "with a full count again")


# --- HASTED ----------------------------------------------------------------------

func test_hasted_adds_forty_percent_move_and_attack_speed_through_modifiers() -> void:
	var plain := _spawn(EliteAffix.Affix.NONE)
	var hasted := _spawn(EliteAffix.Affix.HASTED)
	var plain_move: float = plain.move_speed()
	assert_almost_eq(hasted.move_speed(), plain_move * 1.4, 0.001, "+40 % move speed")
	assert_almost_eq(hasted.attack_speed(), 1.4, 0.001, "+40 % attack speed")
	assert_almost_eq(plain.attack_speed(), 1.0, 0.001, "a plain enemy attacks at 1.0")


func test_hasted_leaves_the_base_move_speed_alone() -> void:
	var hasted := _spawn(EliteAffix.Affix.HASTED)
	var stats := hasted.get_node("StatBlock") as StatBlock
	assert_eq(float(stats.base.get(StatBlock.Stat.MOVE_SPEED, 0.0)), hasted.data.move_speed, "base is the data's speed")


# --- SPLITTING -------------------------------------------------------------------

func test_splitting_copies_are_two_points_round_the_death_spot() -> void:
	var points := AffixSplitting.copy_positions(Vector2(100, 100))
	assert_eq(points.size(), AffixSplitting.COPY_COUNT, "two copies")
	assert_eq(AffixSplitting.COPY_COUNT, 2, "the spec's two copies")
	for point: Vector2 in points:
		assert_almost_eq(point.distance_to(Vector2(100, 100)), AffixSplitting.SPLIT_RADIUS, 0.001, "each copy sits one split radius out")


func test_splitting_copies_spawn_at_thirty_percent_hp() -> void:
	assert_eq(AffixSplitting.copy_hp_for(20), 6, "30 % of 20")
	assert_eq(AffixSplitting.copy_hp_for(1), 1, "never below 1")


func test_splitting_on_death_spawns_two_plain_copies_at_thirty_percent() -> void:
	_wire_world()
	var enemy := _spawn(EliteAffix.Affix.SPLITTING)
	enemy.room = null
	var before: int = _world.get_tree().get_nodes_in_group(Enemy.GROUP).size()
	enemy.affix_behavior.on_death(enemy, _light_hit())
	var copies: Array[Node] = []
	for node: Node in _world.get_tree().get_nodes_in_group(Enemy.GROUP):
		if node != enemy and node is Enemy and not (node as Enemy).elite:
			copies.append(node)
	assert_eq(_world.get_tree().get_nodes_in_group(Enemy.GROUP).size() - before, AffixSplitting.COPY_COUNT, "two copies spawned")
	assert_eq(copies.size(), AffixSplitting.COPY_COUNT, "both are plain, non-elite enemies")
	for node: Node in copies:
		var copy := node as Enemy
		assert_eq(copy.health.current_hp, AffixSplitting.copy_hp_for(copy.health.max_hp), "each copy at 30 % HP")


# --- VAMPIRIC --------------------------------------------------------------------

func test_vampiric_heals_twenty_percent_of_the_damage_dealt() -> void:
	var enemy := _spawn(EliteAffix.Affix.VAMPIRIC)
	enemy.health.current_hp = 5
	enemy.affix_behavior.on_dealt(enemy, 10)
	assert_eq(enemy.health.current_hp, 7, "10 dealt heals 2")


func test_an_enemy_hit_that_lands_reports_its_damage_to_the_vampire() -> void:
	var enemy := _spawn(EliteAffix.Affix.VAMPIRIC)
	enemy.health.current_hp = 5
	enemy.on_dealt_damage(10)
	assert_eq(enemy.health.current_hp, 7, "the attacker hook reaches the affix")


# --- EXPLOSIVE -------------------------------------------------------------------

func test_explosive_blast_hits_players_inside_the_radius_after_the_telegraph() -> void:
	_wire_world()
	var enemy := _spawn(EliteAffix.Affix.EXPLOSIVE)
	enemy.global_position = Vector2.ZERO
	var near := _player_at(Vector2(AffixExplosive.BLAST_RADIUS - 4.0, 0.0))
	var far := _player_at(Vector2(AffixExplosive.BLAST_RADIUS + 40.0, 0.0))
	var near_hp: int = near.health.current_hp
	var far_hp: int = far.health.current_hp
	enemy.affix_behavior.on_death(enemy, _light_hit())
	assert_eq(near.health.current_hp, near_hp, "nothing lands before the telegraph ends")
	await get_tree().create_timer(AffixExplosive.TELEGRAPH_SECONDS + 0.2).timeout
	assert_lt(near.health.current_hp, near_hp, "the player inside the radius is hit")
	assert_eq(far.health.current_hp, far_hp, "the player outside the radius is not")


# --- TELEPORTING -----------------------------------------------------------------

func test_blink_point_lands_behind_the_target_on_the_far_side() -> void:
	var point := AffixTeleporting.blink_point(Vector2.ZERO, Vector2(100, 0))
	assert_almost_eq(point.x, 100.0 + AffixTeleporting.BEHIND_DISTANCE, 0.001, "past the target, away from where it stood")
	assert_almost_eq(point.y, 0.0, 0.001)


func test_teleporting_blinks_after_its_cooldown_and_telegraph() -> void:
	var enemy := _spawn(EliteAffix.Affix.TELEPORTING)
	var target := Node2D.new()
	add_child_autofree(target)
	target.global_position = Vector2(100, 0)
	enemy.target = target
	enemy.global_position = Vector2.ZERO
	var blink := enemy.affix_behavior as AffixTeleporting
	blink.process(AffixTeleporting.BLINK_SECONDS, enemy)
	blink.process(AffixTeleporting.TELEGRAPH_SECONDS / 2.0, enemy)
	assert_almost_eq(enemy.telegraph_progress, 0.5, 0.001, "the telegraph runs from the cooldown end")
	assert_almost_eq(enemy.global_position.x, 0.0, 0.001, "no blink while the telegraph runs")
	blink.process(AffixTeleporting.TELEGRAPH_SECONDS / 2.0, enemy)
	assert_almost_eq(enemy.global_position.x, 100.0 + AffixTeleporting.BEHIND_DISTANCE, 0.001, "it blinks behind the target")
	assert_eq(enemy.telegraph_progress, -1.0, "the telegraph clears on the blink")
