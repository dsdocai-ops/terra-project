extends Node
## Story flags, dialogue state, lore unlocks. Owned by story-dialogue (week 6
## fills it in). Week 1 stub: API shape from SPEC-story-dialogue with an
## in-memory flag set so unlock checks can already be written against it.
## Sync: flags are per player, set on the host for the acting player and
## merged at run end (SPEC-story-dialogue).

signal flag_set(flag: StringName)
signal lore_unlocked(page_id: StringName)
signal miner_rescued(miner_id: StringName)

var _flags: Dictionary[StringName, bool] = {}
var _lore: Dictionary[StringName, bool] = {}


func has_flag(flag: StringName) -> bool:
	return _flags.has(flag)


## Idempotent. TODO(story-dialogue): save when the flag is in UNLOCK_FLAGS.
func set_flag(flag: StringName) -> void:
	if _flags.has(flag):
		return
	_flags[flag] = true
	flag_set.emit(flag)
	Events.story_flag_set.emit(flag)


func flags() -> Array[StringName]:
	var result: Array[StringName] = []
	result.assign(_flags.keys())
	return result


## 1 to 3, derived from flags. TODO(story-dialogue): act transitions.
func act() -> int:
	return 1


func unlock_lore(page_id: StringName) -> void:
	if _lore.has(page_id):
		return
	_lore[page_id] = true
	lore_unlocked.emit(page_id)
	Events.lore_unlocked.emit(page_id)


func lore_unlocked_count() -> int:
	return _lore.size()


## Dialogue condition language. TODO(story-dialogue): all operators.
func evaluate(_condition: Dictionary) -> bool:
	return true


func start_dialogue(_dialogue_id: StringName, _npc: Node = null) -> void:
	pass
