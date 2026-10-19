extends GutTest
## Tests for Damage.compute (SPEC-stats-status). Owned by stats-status.
## Reads the golden table (hand-computed values) and separately covers the
## spec formula pieces: attack scaling, defense mitigation at 0/50/100, min-1,
## crit multiplier, MARK-forced crit, and the ability-power scale.

const GOLDEN_PATH := "res://tests/unit/damage_table.json"
const EPSILON := 0.0001

const BASE_STATS: Dictionary = {
	"MAX_HP": 100.0,
	"ATTACK": 100.0,
	"DEFENSE": 0.0,
	"MOVE_SPEED": 120.0,
	"ATTACK_SPEED": 1.0,
	"DODGE_COOLDOWN": 0.8,
	"CRIT_CHANCE": 0.0,
	"CRIT_DAMAGE": 0.0,
	"ABILITY_POWER": 100.0,
	"COOLDOWN_REDUCTION": 0.0,
	"LUCK": 0.0,
}


func _attacker(overrides: Dictionary = {}) -> StatBlock:
	return _block(_stat_dict(BASE_STATS, overrides))


func _target(overrides: Dictionary = {}) -> StatBlock:
	var base: Dictionary = {}
	for key: String in BASE_STATS:
		base[key] = 0.0
	base["DEFENSE"] = 0.0
	return _block(_stat_dict(base, overrides))


## Turns a String-name -> float dictionary (JSON reads / test literals) into a
## Stat-enum-keyed base dictionary, then merges `overrides` on top.
func _stat_dict(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in base.keys():
		out[StatBlock.Stat[String(key)]] = float(base[key])
	for key: Variant in overrides.keys():
		out[StatBlock.Stat[String(key)]] = float(overrides[key])
	return out


func _block(base: Dictionary) -> StatBlock:
	var sb := StatBlock.new()
	sb.base = base
	add_child_autofree(sb)
	return sb


func _hit(hit: Dictionary = {}) -> HitData:
	var out := HitData.new()
	if hit.has("base_damage"):
		out.base_damage = float(hit["base_damage"])
	if hit.has("multiplier"):
		out.multiplier = float(hit["multiplier"])
	if hit.has("bonus_crit_chance"):
		out.bonus_crit_chance = float(hit["bonus_crit_chance"])
	if hit.has("force_crit"):
		out.force_crit = bool(hit["force_crit"])
	if hit.has("scales_with_ability_power"):
		out.scales_with_ability_power = bool(hit["scales_with_ability_power"])
	return out


func _json_block(data: Variant) -> StatBlock:
	var base: Dictionary = {}
	for key: Variant in (data as Dictionary).keys():
		base[StatBlock.Stat[String(key)]] = float((data as Dictionary)[key])
	var sb := StatBlock.new()
	sb.base = base
	add_child_autofree(sb)
	return sb


func _json_hit(data: Variant) -> HitData:
	var hit := _hit(data)
	hit.base_damage = float((data as Dictionary).get("base_damage", 0.0))
	hit.multiplier = float((data as Dictionary).get("multiplier", 1.0))
	hit.bonus_crit_chance = float((data as Dictionary).get("bonus_crit_chance", 0.0))
	hit.force_crit = bool((data as Dictionary).get("force_crit", false))
	hit.scales_with_ability_power = bool((data as Dictionary).get("scales_with_ability_power", false))
	return hit


# Golden table

func test_golden_table_matches_hand_computed_values() -> void:
	var raw_text := FileAccess.get_file_as_string(GOLDEN_PATH)
	assert_false(raw_text.is_empty(), "golden table reads")
	var parsed: Variant = JSON.parse_string(raw_text)
	assert_true(parsed is Dictionary, "golden table parses to a dictionary")
	var table := parsed as Dictionary
	assert_true(table.has("cases"))
	var cases: Array = table["cases"]
	assert_eq(cases.size(), 12, "one row per hand-computed case")
	for case_row: Variant in cases:
		var row := case_row as Dictionary
		var attacker := _json_block(row["attacker_base"])
		var target := _json_block(row["target_base"])
		var hit := _json_hit(row["hit"])
		var expected: int = int(row["expected"])
		var name: String = String(row["name"])
		var got := Damage.compute(attacker, target, hit)
		assert_eq(got, expected, "golden case '%s' hits the hand-computed value" % name)


func test_golden_rows_are_flagged_correctly() -> void:
	# The row's crit flag must be deterministically decided (chance 0/1 or
	# force_crit), so is_crit is stable across the whole run.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	var table := parsed as Dictionary
	for case_row: Variant in table["cases"] as Array:
		var row := case_row as Dictionary
		var attacker := _json_block(row["attacker_base"])
		var target := _json_block(row["target_base"])
		var hit := _json_hit(row["hit"])
		Damage.compute(attacker, target, hit)
		var crit_chance: float = attacker.get_value(StatBlock.Stat.CRIT_CHANCE) + hit.bonus_crit_chance
		var expected_crit: bool = hit.force_crit or crit_chance >= 1.0
		assert_eq(hit.is_crit, expected_crit, "crit flag for '%s'" % String(row["name"]))


# Formula pieces

func test_plain_hit_is_base_damage() -> void:
	var attacker := _attacker()
	var target := _target()
	var hit := _hit({"base_damage": 20.0})
	assert_eq(Damage.compute(attacker, target, hit), 20)


func test_attack_scales_linearly_from_100() -> void:
	var attacker := _attacker({"ATTACK": 200.0})
	var target := _target()
	var hit := _hit({"base_damage": 20.0})
	assert_eq(Damage.compute(attacker, target, hit), 40, "ATTACK 200 is x2 base damage")


func test_mitigation_at_zero_fifty_hundred_defense() -> void:
	var attacker := _attacker()
	var base_damage := 30.0
	assert_eq(Damage.compute(attacker, _target({"DEFENSE": 0.0}), _hit({"base_damage": base_damage})), 30)
	assert_eq(Damage.compute(attacker, _target({"DEFENSE": 50.0}), _hit({"base_damage": base_damage})), 20)
	assert_eq(Damage.compute(attacker, _target({"DEFENSE": 100.0}), _hit({"base_damage": base_damage})), 15)


func test_defense_cannot_amplify_damage() -> void:
	var attacker := _attacker()
	var hit := _hit({"base_damage": 20.0})
	assert_eq(Damage.compute(attacker, _target({"DEFENSE": -100.0}), hit), 20, "negative defense is clamped to 0")


func test_minimum_damage_is_one() -> void:
	var attacker := _attacker()
	var target := _target({"DEFENSE": 990000.0})
	var hit := _hit({"base_damage": 1.0})
	assert_eq(Damage.compute(attacker, target, hit), 1, "a connecting hit never deals 0")


func test_multiplier_scales_final_damage() -> void:
	var attacker := _attacker()
	var hit := _hit({"base_damage": 20.0, "multiplier": 1.75})
	assert_eq(Damage.compute(attacker, _target(), hit), 35, "backstab +75% multiplies final")


func test_crit_uses_one_point_five_plus_crit_damage() -> void:
	var attacker := _attacker({"CRIT_CHANCE": 1.0, "CRIT_DAMAGE": 0.5})
	var hit := _hit({"base_damage": 20.0})
	assert_eq(Damage.compute(attacker, _target(), hit), 40, "(1.5 + 0.5) x 20")


func test_mark_forces_crit_even_at_zero_chance() -> void:
	var attacker := _attacker({"CRIT_CHANCE": 0.0})
	var hit := _hit({"base_damage": 20.0, "force_crit": true})
	assert_eq(Damage.compute(attacker, _target(), hit), 30, "MARK guarantees the crit")
	assert_true(hit.is_crit)


func test_ability_power_scales_only_ability_hits() -> void:
	var attacker := _attacker({"ABILITY_POWER": 150.0})
	var hit := _hit({"base_damage": 20.0})
	assert_eq(Damage.compute(attacker, _target(), hit), 20, "weapon hit ignores ability power")
	hit.scales_with_ability_power = true
	assert_eq(Damage.compute(attacker, _target(), hit), 30, "ability hit scales 1.0 + 50/100")


func test_crit_roll_is_roughly_the_declared_chance() -> void:
	seed(20241019)
	var attacker := _attacker({"CRIT_CHANCE": 0.5})
	var crits := 0
	var trials := 400
	for i in trials:
		var hit := _hit({"base_damage": 10.0})
		Damage.compute(attacker, _target(), hit)
		if hit.is_crit:
			crits += 1
	assert_between(crits, 150, 250, "400 rolls at 50% crit land in [150, 250]")
