extends GutTest
## Elite core (SPEC-enemies-ai "Elites", W4-A1 part 1): an elite is any
## `EnemyData` with `can_be_elite`; its +100 % HP is a `StatBlock` modifier, never
## a base edit; its death emits `Events.elite_killed` once; it wears the elite
## outline; and its affix travels in the spawn payload. Owned by enemies-ai.
## Sync: `setup` and the affix run on the host before the node enters the tree;
## the flag and affix reach clients in the `EnemySpawnInfo` the MultiplayerSpawner
## sends, so no per-tick sync is involved.

const ENEMY_SCENE := "res://scenes/enemies/enemy_base.tscn"
const ELITE_KIND: StringName = &"hollow_miner"
const OUTLINE_SHADER_PATH: String = "res://scripts/effects/elite_outline.gdshader"
const OUTLINE_NODE: String = "EliteOutline"


func _spawn(kind: StringName, elite: bool, affix: EliteAffix.Affix = EliteAffix.Affix.NONE) -> Enemy:
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	assert_true(enemy.setup(kind, elite, affix), "%s data loads" % kind)
	add_child_autofree(enemy)
	return enemy


func _max_hp(enemy: Enemy) -> float:
	return (enemy.get_node("StatBlock") as StatBlock).get_value(StatBlock.Stat.MAX_HP)


func _base_max_hp(enemy: Enemy) -> float:
	return float((enemy.get_node("StatBlock") as StatBlock).base.get(StatBlock.Stat.MAX_HP, 0.0))


# --- who is an elite -------------------------------------------------------------

func test_an_enemy_data_with_can_be_elite_spawns_as_an_elite() -> void:
	var enemy := _spawn(ELITE_KIND, true)
	assert_true(enemy.elite, "the grub's data allows an elite, so the flag holds")


func test_a_plain_spawn_is_not_an_elite() -> void:
	var enemy := _spawn(ELITE_KIND, false)
	assert_false(enemy.elite)


func test_an_enemy_data_without_can_be_elite_refuses_the_flag() -> void:
	var data := EnemyData.find(ELITE_KIND)
	var was: bool = data.can_be_elite
	data.can_be_elite = false
	var enemy := _spawn(ELITE_KIND, true)
	data.can_be_elite = was
	assert_false(enemy.elite, "the data says no elites, so the spawn is plain")


# --- +100 % HP through a modifier ------------------------------------------------

func test_elite_max_hp_is_exactly_double_the_plain_max_hp() -> void:
	var plain := _spawn(ELITE_KIND, false)
	var elite := _spawn(ELITE_KIND, true)
	assert_almost_eq(_max_hp(elite), _max_hp(plain) * 2.0, 0.001, "+100 % HP")
	assert_eq(elite.health.max_hp, roundi(_max_hp(plain) * 2.0), "Health reads the doubled MAX_HP")


func test_the_elite_base_max_hp_is_not_edited() -> void:
	var plain := _spawn(ELITE_KIND, false)
	var elite := _spawn(ELITE_KIND, true)
	assert_eq(_base_max_hp(elite), _base_max_hp(plain), "the doubling is a modifier, the base stays put")


func test_the_elite_hp_is_one_modifier_under_the_elite_source() -> void:
	var elite := _spawn(ELITE_KIND, true)
	var stats := elite.get_node("StatBlock") as StatBlock
	var rows: int = 0
	for modifier: Dictionary in stats._modifiers:
		if int(modifier["stat"]) == StatBlock.Stat.MAX_HP and modifier["source"] == &"elite":
			rows += 1
	assert_eq(rows, 1, "exactly one elite HP modifier row")


# --- death ------------------------------------------------------------------------

func test_an_elite_death_emits_elite_killed_once() -> void:
	var elite := _spawn(ELITE_KIND, true)
	watch_signals(Events)
	elite.apply_hit(100000)
	assert_signal_emit_count(Events, "elite_killed", 1, "one death, one elite_killed")
	assert_signal_emitted(Events, "enemy_killed", "the death is still an enemy_killed too")


func test_a_plain_death_does_not_emit_elite_killed() -> void:
	var plain := _spawn(ELITE_KIND, false)
	watch_signals(Events)
	plain.apply_hit(100000)
	assert_signal_emit_count(Events, "elite_killed", 0, "a plain enemy is not an elite")


# --- outline ----------------------------------------------------------------------

func test_an_elite_wears_the_outline_and_a_plain_enemy_does_not() -> void:
	var elite := _spawn(ELITE_KIND, true)
	var plain := _spawn(ELITE_KIND, false)
	var outline := elite.get_node_or_null(OUTLINE_NODE) as Polygon2D
	assert_not_null(outline, "the elite has its outline node")
	var material := outline.material as ShaderMaterial
	assert_not_null(material, "the outline carries a ShaderMaterial")
	assert_eq(material.shader.resource_path, OUTLINE_SHADER_PATH, "with the elite outline shader")
	assert_null(plain.get_node_or_null(OUTLINE_NODE), "a plain enemy has no outline")


# --- affix --------------------------------------------------------------------------

func test_the_affix_is_stored_on_an_elite() -> void:
	var elite := _spawn(ELITE_KIND, true, EliteAffix.Affix.SHIELDED)
	assert_eq(elite.affix, EliteAffix.Affix.SHIELDED)


func test_a_plain_enemy_ignores_an_affix_and_keeps_none() -> void:
	var plain := _spawn(ELITE_KIND, false, EliteAffix.Affix.SHIELDED)
	assert_eq(plain.affix, EliteAffix.Affix.NONE, "only an elite carries an affix")


func test_the_affix_travels_in_the_spawn_payload() -> void:
	var info := EnemySpawnInfo.new(ELITE_KIND, Vector2(10, 20), true, 7, EliteAffix.Affix.HASTED)
	var back := EnemySpawnInfo.from_dict(info.to_dict())
	assert_eq(back.affix, EliteAffix.Affix.HASTED, "every peer reads the same affix")
	assert_true(back.elite)
