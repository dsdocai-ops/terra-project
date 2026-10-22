extends GutTest
## Tests for Damage.compute (SPEC-stats-status). Owned by stats-status.
## Reads the golden table (hand-computed values) and separately covers the
## spec formula pieces: attack scaling, defense mitigation at 0/50/100, min-1,
## crit multiplier, MARK-forced crit, and the ability-power scale.
##
## The G23 section at the end covers the formula's three `status_mult` terms and
## its other crit rule: Kindling's +0.25 on a BURN target, the +1.0 a FREEZE
## target takes, UNRAVEL's stacks * 0.1, the MARK that forces the crit from the
## *target's* component instead of the hit's own flag, and the fact that a marked
## hit consumes no draw. Each term is asserted alone at a hand-computed number
## and then all three composed, so a missing or double-counted term cannot hide
## behind the others.

const GOLDEN_PATH := "res://tests/unit/damage_table.json"
const EPSILON := 0.0001

## The node names the formula's two component lookups use: the target's
## `StatusEffects` (where every target-side term is read) and the attacker's
## `EffectHost` (where the two attacker-side relics are read).
const STATUS_NODE: NodePath = ^"StatusEffects"
const STATUS_NAME: StringName = &"StatusEffects"
const STAT_BLOCK_NODE: NodePath = ^"StatBlock"
const STAT_BLOCK_NAME: StringName = &"StatBlock"

## The two attacker-side relics SPEC-stats-status's formula names. Neither is
## content until W4-B6 (G32…G35), so a case attaches a do-nothing marker `Effect`
## under the relic's own id — which is all the formula's lookup asks about.
const MARKER_EFFECT_SCRIPT: String = "res://tests/helpers/relic_marker_effect.gd"
const KINDLING: StringName = &"kindling"
const PERMAFROST: StringName = &"permafrost"

## The seed the no-draw case uses for both generators.
const SEED: int = 20241019

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


func before_each() -> void:
	# The formula reads statuses off the target's component and relics off the
	# attacker's host, and that component applies nothing on a peer that does not
	# resolve statuses — so the host branch is made explicit here, the way
	# tests/unit/test_status_effects.gd does it, and undone in after_each because
	# autoload state is shared across the whole GUT run (LESSONS).
	NetworkManager.start_solo()


func after_each() -> void:
	NetworkManager.disconnect_all()


func _attacker(overrides: Dictionary = {}) -> StatBlock:
	return _block(_attacker_table(overrides))


func _target(overrides: Dictionary = {}) -> StatBlock:
	return _block(_target_table(overrides))


## The attacker's base stats: the default table plus String-name `overrides`.
func _attacker_table(overrides: Dictionary = {}) -> Dictionary:
	return _stat_dict(BASE_STATS, overrides)


## The target's base stats: zeroes except DEFENSE, plus `overrides`. A target's
## ATTACK is irrelevant to the formula, and a zero base makes every hand-computed
## number below the attacker's.
func _target_table(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {}
	for key: String in BASE_STATS:
		base[key] = 0.0
	base["DEFENSE"] = 0.0
	return _stat_dict(base, overrides)


## Turns a String-name -> float dictionary (JSON reads / test literals) into a
## Stat-enum-keyed base dictionary, then merges `overrides` on top.
func _stat_dict(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in base.keys():
		out[StatBlock.Stat[String(key)]] = float(base[key])
	for key: Variant in overrides.keys():
		out[StatBlock.Stat[String(key)]] = float(overrides[key])
	return out


## A JSON `base` object as a Stat-enum-keyed dictionary.
func _stat_table_from_json(data: Variant) -> Dictionary:
	var base: Dictionary = {}
	for key: Variant in (data as Dictionary).keys():
		base[StatBlock.Stat[String(key)]] = float((data as Dictionary)[key])
	return base


func _block(base: Dictionary) -> StatBlock:
	var sb := StatBlock.new()
	sb.base = base
	add_child_autofree(sb)
	return sb


## A target `StatBlock` on an entity that also carries the `StatusEffects`
## component the formula reads every target-side term from, with `statuses`
## applied first. Each entry is `{"status": "BURN", "stacks": 2}` — an enum
## member by name, so the golden file can carry status rows as plain JSON.
##
## The component is what makes a status term reachable; an entity that carries
## one and no statuses contributes exactly what a bare week-2 fixture did
## (multiplier 1.0, no forced crit), which is why the week-2 golden rows are
## unchanged by both this fixture and the terms it exists for.
func _status_target(base: Dictionary, statuses: Array) -> StatBlock:
	var entity := Node2D.new()
	entity.name = &"Target"
	add_child_autofree(entity)
	var block := StatBlock.new()
	block.name = STAT_BLOCK_NAME
	entity.add_child(block)
	block.base = base
	var component := StatusEffects.new()
	component.name = STATUS_NAME
	entity.add_child(component)
	for row: Variant in statuses:
		var spec := row as Dictionary
		var status: StatusEffects.Status = StatusEffects.Status[String(spec["status"])]
		component.apply_status(status, int(spec.get("stacks", 1)))
	return block


## The attacker `StatBlock` on a real player carrying `relics` on its
## `EffectHost` — the shape SPEC-stats-status's two attacker-side terms are read
## from. The player scene is composed here the way `test_status_effects.gd` does
## it: `player.tscn` is Dev A's and its component nodes are bare placeholders
## (**blocked on Dev A (W2-A1)**), so this fixture swaps a real `StatBlock` and a
## real `EffectHost` in.
func _relic_attacker(base: Dictionary, relics: Array) -> StatBlock:
	var player: Player = (load(EffectHostPlayer.PLAYER_SCENE) as PackedScene).instantiate() as Player
	player.name = &"RelicAttacker"
	add_child_autofree(player)
	var bare: Node = player.get_node_or_null(STAT_BLOCK_NODE)
	if bare != null:
		player.remove_child(bare)
		bare.free()
	var block := StatBlock.new()
	block.name = STAT_BLOCK_NAME
	player.add_child(block)
	block.base = base
	var host := EffectHostPlayer.install(player)
	for id: Variant in relics:
		_attach_relic(host, StringName(id))
	return block


## Attaches one marker relic under `id`: a do-nothing `Effect`, since neither
## Kindling nor Permafrost is content until W4-B6 and the formula's lookup only
## asks whether the id is held.
func _attach_relic(host: EffectHost, id: StringName) -> void:
	var relic := ContentData.new()
	relic.id = id
	relic.display_name = String(id)
	relic.effect_script = load(MARKER_EFFECT_SCRIPT) as GDScript
	host.add(relic)


## The `StatusEffects` component on `block`'s entity, or null when the entity
## carries none — the week-2 shape, and the reason a null component still means a
## `status_mult` of 1.0 with no forced crit.
func _statuses_of(block: StatBlock) -> StatusEffects:
	var entity: Node = block.get_parent()
	if entity == null:
		return null
	return entity.get_node_or_null(STATUS_NODE) as StatusEffects


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


## The row's attacker: a bare `StatBlock` unless the row names relics, in which
## case it is one on a player whose `EffectHost` holds them.
func _json_attacker(row: Dictionary) -> StatBlock:
	var base := _stat_table_from_json(row["attacker_base"])
	var relics: Array = row.get("attacker_relics", []) as Array
	if relics.is_empty():
		return _block(base)
	return _relic_attacker(base, relics)


## The row's target: a bare `StatBlock` unless the row names statuses, in which
## case it is one on an entity carrying the `StatusEffects` component those
## statuses were applied to.
func _json_target(row: Dictionary) -> StatBlock:
	var base := _stat_table_from_json(row["target_base"])
	var statuses: Array = row.get("target_statuses", []) as Array
	if statuses.is_empty():
		return _block(base)
	return _status_target(base, statuses)


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
	assert_eq(cases.size(), 18, "one row per hand-computed case: the 12 week-2 rows plus the 6 status rows")
	for case_row: Variant in cases:
		var row := case_row as Dictionary
		var attacker := _json_attacker(row)
		var target := _json_target(row)
		var hit := _json_hit(row["hit"])
		var expected: int = int(row["expected"])
		var name: String = String(row["name"])
		var got := Damage.compute(attacker, target, hit, null, _statuses_of(target))
		assert_eq(got, expected, "golden case '%s' hits the hand-computed value" % name)


func test_golden_rows_are_flagged_correctly() -> void:
	# The row's crit flag must be deterministically decided — crit chance 0/1,
	# the hit's own force_crit, or a MARK on the target — so is_crit is stable
	# across the whole run. The flag is read *before* the hit, because a marked
	# hit consumes the mark it read.
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN_PATH))
	var table := parsed as Dictionary
	for case_row: Variant in table["cases"] as Array:
		var row := case_row as Dictionary
		var attacker := _json_attacker(row)
		var target := _json_target(row)
		var statuses := _statuses_of(target)
		var hit := _json_hit(row["hit"])
		var forced: bool = hit.force_crit or (statuses != null and statuses.mark_forces_crit())
		Damage.compute(attacker, target, hit, null, statuses)
		var crit_chance: float = attacker.get_value(StatBlock.Stat.CRIT_CHANCE) + hit.bonus_crit_chance
		var expected_crit: bool = forced or crit_chance >= 1.0
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


## Rolls `rolls` hits at 50% crit through one seeded generator and returns the
## crit flags in order, so two runs with the same seed can be compared.
func _crit_sequence(crit_seed: int, rolls: int) -> Array[bool]:
	var rng := RandomNumberGenerator.new()
	rng.seed = crit_seed
	var attacker := _attacker({"CRIT_CHANCE": 0.5})
	var out: Array[bool] = []
	for i in rolls:
		var hit := _hit({"base_damage": 10.0})
		Damage.compute(attacker, _target(), hit, rng)
		out.append(hit.is_crit)
	return out


func test_crit_roll_is_roughly_the_declared_chance() -> void:
	# An injected seeded generator makes the band deterministic; the formula no
	# longer reads the global RNG, so seeding that would prove nothing.
	var rng := RandomNumberGenerator.new()
	rng.seed = 20241019
	var attacker := _attacker({"CRIT_CHANCE": 0.5})
	var crits := 0
	var trials := 400
	for i in trials:
		var hit := _hit({"base_damage": 10.0})
		Damage.compute(attacker, _target(), hit, rng)
		if hit.is_crit:
			crits += 1
	assert_between(crits, 150, 250, "400 rolls at 50% crit land in [150, 250]")


func test_injected_rng_replays_the_same_crit_sequence_for_a_seed() -> void:
	var first := _crit_sequence(20241019, 64)
	var second := _crit_sequence(20241019, 64)
	assert_eq(first, second, "the same seed replays the same crit sequence")


func test_different_seeds_move_the_crit_sequence() -> void:
	var first := _crit_sequence(20241019, 64)
	var other := _crit_sequence(20241020, 64)
	assert_ne(first, other, "a different seed gives a different crit sequence")


func test_null_rng_still_rolls_crits() -> void:
	# No caller generator: the Damage-owned fallback must keep rolling near the
	# declared chance rather than freezing at always-crit or never-crit.
	var attacker := _attacker({"CRIT_CHANCE": 0.5})
	var crits := 0
	var trials := 400
	for i in trials:
		var hit := _hit({"base_damage": 10.0})
		Damage.compute(attacker, _target(), hit)
		if hit.is_crit:
			crits += 1
	assert_between(crits, 100, 300, "the fallback generator still rolls near the declared chance")


# --- G23: the three `status_mult` terms, the marked crit, the no-draw rule ----
#
# Every hit below is 20 base damage from an ATTACK 100 attacker at 0 % crit
# chance against a DEFENSE 0 target, so `raw` is 20 and the only thing moving is
# the term under test. Each term is asserted alone first — with the same target
# against an attacker that does *not* have the relic, so a term that fired
# unconditionally could not pass — and the three are composed at the end.

func test_kindling_adds_a_quarter_against_a_burning_target() -> void:
	var burning := _status_target(_target_table(), [{"status": "BURN", "stacks": 1}])
	var statuses := _statuses_of(burning)
	var with_kindling := _relic_attacker(_attacker_table(), [KINDLING])
	assert_eq(Damage.compute(_attacker(), burning, _hit({"base_damage": 20.0}), null, statuses), 20,
		"a burning target takes the plain 20 from an attacker with no Kindling")
	assert_eq(Damage.compute(with_kindling, burning, _hit({"base_damage": 20.0}), null, statuses), 25,
		"and 20 * 1.25 with it: the formula's '+0.25 Kindling on BURN'")
	var unhurt := _target()
	assert_eq(Damage.compute(with_kindling, unhurt, _hit({"base_damage": 20.0}), null, _statuses_of(unhurt)), 20,
		"the quarter is conditional on the target burning, not on the relic alone")


func test_unravel_stacks_raise_the_damage_taken() -> void:
	var unravelled := _status_target(_target_table(), [{"status": "UNRAVEL", "stacks": 3}])
	assert_eq(Damage.compute(_attacker(), unravelled, _hit({"base_damage": 20.0}), null, _statuses_of(unravelled)), 26,
		"three UNRAVEL stacks are +0.3: 20 * 1.3")


func test_the_freeze_double_lasts_for_one_hit() -> void:
	var frozen := _status_target(_target_table(), [{"status": "FREEZE", "stacks": 1}])
	var statuses := _statuses_of(frozen)
	var attacker := _attacker()
	assert_eq(Damage.compute(attacker, frozen, _hit({"base_damage": 20.0}), null, statuses), 40,
		"the next hit on a frozen target takes the +1.0: 20 * 2.0")
	assert_eq(Damage.compute(attacker, frozen, _hit({"base_damage": 20.0}), null, statuses), 20,
		"and the one after that does not — the double is spent once")


func test_permafrost_makes_the_freeze_bonus_apply_to_every_hit() -> void:
	var frozen := _status_target(_target_table(), [{"status": "FREEZE", "stacks": 1}])
	var statuses := _statuses_of(frozen)
	var with_permafrost := _relic_attacker(_attacker_table(), [PERMAFROST])
	assert_eq(Damage.compute(with_permafrost, frozen, _hit({"base_damage": 20.0}), null, statuses), 40,
		"the first hit takes the +1.0: 20 * 2.0")
	assert_eq(Damage.compute(with_permafrost, frozen, _hit({"base_damage": 20.0}), null, statuses), 40,
		"and Permafrost's 'makes it always': so does the second")
	assert_eq(Damage.compute(_attacker(), frozen, _hit({"base_damage": 20.0}), null, statuses), 20,
		"while an attacker without it gets a plain 20 back")


func test_mark_forces_the_crit_and_is_consumed_once() -> void:
	var marked := _status_target(_target_table(), [{"status": "MARK", "stacks": 1}])
	var statuses := _statuses_of(marked)
	var attacker := _attacker({"CRIT_CHANCE": 0.0})
	var first := _hit({"base_damage": 20.0})
	assert_eq(Damage.compute(attacker, marked, first, null, statuses), 30,
		"a marked target is crit at 0 % crit chance: 20 * 1.5")
	assert_true(first.is_crit, "and the hit records it")
	assert_false(statuses.has(StatusEffects.Status.MARK), "the mark is consumed by the hit it forced")
	var second := _hit({"base_damage": 20.0})
	assert_eq(Damage.compute(attacker, marked, second, null, statuses), 20, "so the next hit is a plain one")
	assert_false(second.is_crit, "with nothing left to force it")


func test_a_marked_hit_consumes_no_crit_roll() -> void:
	# W3-B1's rule, now reachable through the target's component instead of only
	# the hit's own flag: the forced crit short-circuits before the draw, so a
	# marked hit must leave the generator exactly where it was. Two generators at
	# one seed make that visible without reaching into the generator: four plain
	# hits after the marked one must read what the marked one would have read.
	var marked := _status_target(_target_table(), [{"status": "MARK", "stacks": 1}])
	var plain := _target()
	var attacker := _attacker({"CRIT_CHANCE": 0.5})

	var marked_rng := RandomNumberGenerator.new()
	marked_rng.seed = SEED
	var forced := _hit({"base_damage": 10.0})
	Damage.compute(attacker, marked, forced, marked_rng, _statuses_of(marked))
	assert_true(forced.is_crit, "the marked hit crits")

	var control_rng := RandomNumberGenerator.new()
	control_rng.seed = SEED
	for i in 4:
		var after := _hit({"base_damage": 10.0})
		Damage.compute(attacker, plain, after, marked_rng)
		var control := _hit({"base_damage": 10.0})
		Damage.compute(attacker, plain, control, control_rng)
		assert_eq([after.is_crit, after.final_damage], [control.is_crit, control.final_damage],
			"draw %d is what the generator would have given had the marked hit drawn nothing" % i)


func test_all_three_terms_compose_on_one_hand_computed_hit() -> void:
	# +0.25 Kindling on BURN, +1.0 on FREEZE, +0.5 for five UNRAVEL stacks:
	# 1 + 0.25 + 1.0 + 0.5 = 2.75, so 20 * 2.75 = 55 on one hit.
	var target := _status_target(_target_table(), [
		{"status": "BURN", "stacks": 1},
		{"status": "FREEZE", "stacks": 1},
		{"status": "UNRAVEL", "stacks": 5},
	])
	var statuses := _statuses_of(target)
	var attacker := _relic_attacker(_attacker_table(), [KINDLING, PERMAFROST])
	assert_eq(Damage.compute(attacker, target, _hit({"base_damage": 20.0}), null, statuses), 55,
		"all three terms on one hit")
	assert_eq(Damage.compute(_attacker(), target, _hit({"base_damage": 20.0}), null, statuses), 30,
		"and without the relics, with the freeze's double already spent, only UNRAVEL's +0.5 is left")
