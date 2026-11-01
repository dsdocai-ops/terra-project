extends GutTest
## Tests for Stone Skin (SPEC-abilities section 8, Earth; SINKHOLE_SPEC "immune to
## knockback and take 50% less damage"): the 50% is a StatBlock DEFENSE modifier
## under the source `stone_skin` that halves the damage mitigation, knockback
## immunity is a flag on the caster's Hurtbox, base stats are never written, and
## both come off when the cast ends. Owned by abilities. Sync: host only. The
## caster is a real Player scene, so the modifier and the flag are read where the
## damage path reads them.

const DATA_PATH: String = "res://data/abilities/stone_skin.tres"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const BASE_DEFENSE: float = 50.0

var _data: AbilityData
var _owner: Player
var _stats: StatBlock
var _hurtbox: Hurtbox


func before_each() -> void:
	_data = load(DATA_PATH) as AbilityData
	_owner = load(PLAYER_SCENE).instantiate() as Player
	add_child_autofree(_owner)
	_stats = _owner.get_node("StatBlock") as StatBlock
	_stats.set_base(StatBlock.Stat.DEFENSE, BASE_DEFENSE)
	_hurtbox = _owner.get_node("Hurtbox") as Hurtbox


func _cast() -> StoneSkinCast:
	var cast := _data.cast_scene.instantiate() as StoneSkinCast
	cast.setup(_owner, _data, 1, Vector2.ZERO, Vector2.RIGHT)
	add_child_autofree(cast)
	return cast


## The final damage of one 300-base hit from a fresh attacker on the owner.
func _damage_taken() -> int:
	var attacker := StatBlock.new()
	attacker.base = {StatBlock.Stat.ATTACK: 100.0}
	var hit := HitInfo.new()
	hit.base_damage = 300.0
	var dealt: int = Damage.compute(attacker, _stats, hit)
	attacker.free()
	return dealt


func test_the_buff_halves_the_damage_taken() -> void:
	var before: int = _damage_taken()
	_cast()
	var after: int = _damage_taken()
	assert_eq(before, 200, "a 300 hit deals 200 through defense 50")
	assert_eq(after, 100, "under Stone Skin the same hit deals half: 100")


func test_the_buff_is_a_defense_modifier_and_base_defense_is_never_written() -> void:
	_cast()
	assert_almost_eq(_stats.get_value(StatBlock.Stat.DEFENSE), 2.0 * BASE_DEFENSE + 100.0, 0.001, "the buff adds 100 plus the current defense")
	assert_almost_eq(float(_stats.base[StatBlock.Stat.DEFENSE]), BASE_DEFENSE, 0.001, "the base defense is untouched")


func test_the_caster_is_immune_to_knockback_while_the_cast_lasts() -> void:
	assert_false(_hurtbox.knockback_immune, "no immunity before the cast")
	_cast()
	assert_true(_hurtbox.knockback_immune, "the caster shrugs off knockback during the cast")


func test_the_buff_and_the_immunity_end_with_the_cast() -> void:
	var cast := _cast()
	cast.get_parent().remove_child(cast)
	cast.free()
	assert_almost_eq(_stats.get_value(StatBlock.Stat.DEFENSE), BASE_DEFENSE, 0.001, "the defense modifier is removed with the cast")
	assert_false(_hurtbox.knockback_immune, "the knockback immunity ends with the cast")


func test_a_cast_with_no_player_buffs_nothing_and_does_not_fail() -> void:
	var cast := _data.cast_scene.instantiate() as StoneSkinCast
	cast.setup(null, _data, 1, Vector2.ZERO, Vector2.RIGHT)
	add_child_autofree(cast)
	assert_almost_eq(_stats.get_value(StatBlock.Stat.DEFENSE), BASE_DEFENSE, 0.001, "the owner's defense is unchanged")
	assert_false(_hurtbox.knockback_immune, "the owner gains no immunity")
