class_name StoneSkinCast
extends AbilityCast
## Stone Skin (SPEC-abilities section 8, Earth; SINKHOLE_SPEC "become immune to
## knockback and take 50% less damage"). For the cast's life the caster gets two
## things on the host: a DEFENSE modifier under SOURCE, and the knockback immunity
## flag on its Hurtbox. Damage mitigation is 100 / (100 + defense), so adding
## 100 plus the current defense halves it exactly. Base stats are never written;
## the modifier and the flag both come off when the cast frees. Owned by abilities.
## Sync: host only. The caster's copy never applies either.

const SOURCE: StringName = &"stone_skin"

var _stats: StatBlock = null
var _hurtbox: Hurtbox = null
var _handle: int = 0


func _perform() -> void:
	if player == null:
		return
	_stats = player.get_node_or_null("StatBlock") as StatBlock
	_hurtbox = player.get_node_or_null("Hurtbox") as Hurtbox
	if _stats != null:
		var defense: float = _stats.get_value(StatBlock.Stat.DEFENSE)
		_handle = _stats.add_modifier(StatBlock.Stat.DEFENSE, Damage.MITIGATION_BASE + defense, 0.0, SOURCE)
	if _hurtbox != null:
		_hurtbox.knockback_immune = true


func _exit_tree() -> void:
	if _stats != null and is_instance_valid(_stats):
		_stats.remove_modifier(_handle)
	if _hurtbox != null and is_instance_valid(_hurtbox):
		_hurtbox.knockback_immune = false
	_stats = null
	_hurtbox = null
