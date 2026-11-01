class_name ClassSkill
extends Node
## The Shift class skill (SPEC-classes-characters "class_skill on Shift"): a node a
## class instances on its player, with its own cooldown. Owned by
## classes-characters. Sync: host-authoritative. The host runs the cooldown and the
## host's copy performs. ClassController refuses a client's request before the skill
## is asked, so a client never starts a cooldown. A subclass overrides `_perform()`
## for what the skill does.

## Seconds the skill waits after a use before it is ready again.
@export var cooldown_seconds: float = 8.0

## The node whose TimeManager scale runs the cooldown: the player the controller sits
## on. Null means this node, which is how a bare skill runs in tests.
var timed_node: Node = null

var _cooldown_left: float = 0.0


## Runs the cooldown for `delta` seconds of the timed node's scaled time. Called by
## ClassController each physics frame; tests call it directly.
func tick(delta: float) -> void:
	var node: Node = timed_node if timed_node != null else self
	_cooldown_left = maxf(_cooldown_left - delta * TimeManager.scale_for(node), 0.0)


## True when the skill can be used now: no cooldown is running.
func is_ready() -> bool:
	return _cooldown_left <= 0.0


## Seconds of cooldown left, 0.0 when ready.
func cooldown_left() -> float:
	return _cooldown_left


## Performs the skill and starts its cooldown. Returns false, and performs nothing,
## while the cooldown runs.
func use() -> bool:
	if not is_ready():
		return false
	_cooldown_left = maxf(cooldown_seconds, 0.0)
	_perform()
	return true


## The skill's effect. The base does nothing; each class skill overrides it.
func _perform() -> void:
	pass
