extends Node
## One place that answers "how fast does time move for this entity right now".
## Enemies and enemy projectiles multiply their delta by scale_for(self);
## players in the PLAYER group ignore the global enemy stack but a per-entity
## override (e.g. hit-stop) still applies to them. Never touches the engine's
## global time-scale. Owned by time-manager.
## Sync: host decides every time effect and broadcasts the start as a reliable
## RPC (time_effect_applied / entity_time_applied); expiry is computed locally
## from the same duration, so frozen entities simply report the same values
## and MultiplayerSynchronizer traffic keeps flowing.

enum Group { PLAYER, ENEMY }

signal enemy_time_changed(scale: float)

const HIT_STOP_SOURCE := &"hit_stop"
const DEFAULT_SCALE := 1.0

## node instance_id -> Group.
var _groups: Dictionary[int, Group] = {}
## Group -> array of {source, factor, expires_on_frame} for the global stacks.
var _global_effects: Dictionary[int, Array] = {}
## node instance_id -> array of {source, factor, expires_on_frame}.
var _entity_effects: Dictionary[int, Array] = {}
var _last_enemy_scale: float = DEFAULT_SCALE
## Active scaled one-shot timers (see timer()).
var _scaled_timers: Array[ScaledTimer] = []


func _physics_process(delta: float) -> void:
	_prune_dead_nodes()
	_expire_effects()
	_tick_scaled_timers(delta)


## Current time multiplier for a node (1.0 = normal, 0.0 = stopped). A
## per-entity override always wins; otherwise PLAYER-group and unregistered
## nodes run at normal speed and only ENEMY-group nodes take the global stack.
func scale_for(node: Node) -> float:
	var id := node.get_instance_id()
	var entity_min := _min_factor(_entity_effects.get(id, []) as Array)
	if entity_min >= 0.0:
		return entity_min
	if not _groups.has(id):
		return DEFAULT_SCALE
	return _min_global(_groups[id])


## Called in _ready by player and enemy scripts to join a time group.
func set_group(node: Node, group: Group) -> void:
	_groups[node.get_instance_id()] = group


func slow_enemies(factor: float, seconds: float, source: StringName) -> void:
	_apply_global(Group.ENEMY, clampf(factor, 0.0, 1.0), seconds, source, true)


func stop_enemies(seconds: float, source: StringName) -> void:
	_apply_global(Group.ENEMY, 0.0, seconds, source, true)


## Cancel a slow or stop early (e.g. Deadeye release). Removes every global and
## per-entity effect carrying that source.
func clear_source(source: StringName) -> void:
	for group: int in _global_effects.keys():
		var list: Array = _global_effects[group]
		for i in range(list.size() - 1, -1, -1):
			if list[i]["source"] == source:
				list.remove_at(i)
		if list.is_empty():
			_global_effects.erase(group)
	for id: int in _entity_effects.keys():
		var list: Array = _entity_effects[id]
		for i in range(list.size() - 1, -1, -1):
			if list[i]["source"] == source:
				list.remove_at(i)
		if list.is_empty():
			_entity_effects.erase(id)
	_emit_enemy_scale_changed_if_changed()


## Single-target override (Frozen Clone taunt target, Crimson Leech slow).
func set_entity_scale(node: Node, factor: float, seconds: float, source: StringName) -> void:
	_apply_entity(node, clampf(factor, 0.0, 1.0), seconds, source, true)


## Freezes exactly `a` and `b` for `frames` physics frames; the camera, the
## HUD, and everyone else keep running. 3 light, 6 heavy, 10 boss kill.
func hit_stop(a: Node, b: Node, frames: int) -> void:
	var frames_left := maxi(frames, 1)
	_set_or_replace_effect(_entity_effects, a.get_instance_id(), HIT_STOP_SOURCE, 0.0, frames_left)
	_set_or_replace_effect(_entity_effects, b.get_instance_id(), HIT_STOP_SOURCE, 0.0, frames_left)
	var seconds := float(frames_left) / float(Engine.physics_ticks_per_second)
	_broadcast_entity(a, 0.0, seconds, HIT_STOP_SOURCE)
	_broadcast_entity(b, 0.0, seconds, HIT_STOP_SOURCE)


## Scaled one-shot timer for enemy gameplay (plain engine Timers and
## create_timer are forbidden on enemies for anything gameplay-relevant). The
## returned signal fires once after `seconds` of time scaled by scale_for(node).
func timer(node: Node, seconds: float) -> Signal:
	var scaled := ScaledTimer.new()
	scaled.node_id = node.get_instance_id()
	scaled.remaining = seconds
	_scaled_timers.append(scaled)
	return scaled.timeout


## Rewind hook (Time Hourglass). Week 4 per spec scope; the API shape is kept
## so effect-system can register against it.
func register_rewindable(_node: Node, _sampler: Callable, _restorer: Callable) -> void:
	pass


func unregister_rewindable(_node: Node) -> void:
	pass


func rewind(_node: Node, _seconds: float) -> void:
	pass


## Host -> clients: a global time effect started. Clients apply the same
## duration locally so expiry stays in lockstep.
@rpc("authority", "call_local", "reliable")
func time_effect_applied(group: int, factor: float, seconds: float, source: StringName) -> void:
	_apply_global(group, factor, seconds, source, false)


## Host -> clients: a per-entity time effect started. `path` is relative to
## the world root so it resolves on every peer's identical tree.
@rpc("authority", "call_local", "reliable")
func entity_time_applied(path: NodePath, factor: float, seconds: float, source: StringName) -> void:
	var node := _resolve_world_path(path)
	if node == null:
		push_warning("[time] entity_time_applied: no node at %s" % path)
		return
	_apply_entity(node, factor, seconds, source, false)


func _apply_global(group: int, factor: float, seconds: float, source: StringName, broadcast: bool) -> void:
	if seconds <= 0.0:
		return
	var frames := maxi(roundi(seconds * float(Engine.physics_ticks_per_second)), 1)
	_set_or_replace_effect(_global_effects, group, source, factor, frames)
	_emit_enemy_scale_changed_if_changed()
	if broadcast:
		_broadcast_time_effect(group, factor, seconds, source)


func _apply_entity(node: Node, factor: float, seconds: float, source: StringName, broadcast: bool) -> void:
	if seconds <= 0.0:
		return
	var frames := maxi(roundi(seconds * float(Engine.physics_ticks_per_second)), 1)
	_set_or_replace_effect(_entity_effects, node.get_instance_id(), source, factor, frames)
	if broadcast:
		_broadcast_entity(node, factor, seconds, source)


func _set_or_replace_effect(container: Dictionary, key: int, source: StringName, factor: float, frames: int) -> void:
	var entry := {"source": source, "factor": factor, "expires_on_frame": Engine.get_physics_frames() + frames}
	var list: Array = container.get(key, []) as Array
	for i in list.size():
		if list[i]["source"] == source:
			list[i] = entry
			container[key] = list
			return
	list.append(entry)
	container[key] = list


func _min_global(group: int) -> float:
	var min_factor := _min_factor(_global_effects.get(group, []) as Array)
	return DEFAULT_SCALE if min_factor < 0.0 else min_factor


## Smallest active factor in `effects`, or -1.0 when there is none active.
func _min_factor(effects: Array) -> float:
	if effects.is_empty():
		return -1.0
	var min_factor := DEFAULT_SCALE
	var frame := Engine.get_physics_frames()
	for effect: Dictionary in effects:
		if int(effect["expires_on_frame"]) <= frame:
			continue
		min_factor = minf(min_factor, float(effect["factor"]))
	return min_factor


func _emit_enemy_scale_changed_if_changed() -> void:
	var scale := _min_global(Group.ENEMY)
	if not is_equal_approx(scale, _last_enemy_scale):
		_last_enemy_scale = scale
		enemy_time_changed.emit(scale)


func _expire_effects() -> void:
	var frame := Engine.get_physics_frames()
	var enemy_changed := false
	for group: int in _global_effects.keys():
		var list: Array = _global_effects[group]
		for i in range(list.size() - 1, -1, -1):
			if int(list[i]["expires_on_frame"]) <= frame:
				list.remove_at(i)
				if group == Group.ENEMY:
					enemy_changed = true
		if list.is_empty():
			_global_effects.erase(group)
	for id: int in _entity_effects.keys():
		var list: Array = _entity_effects[id]
		for i in range(list.size() - 1, -1, -1):
			if int(list[i]["expires_on_frame"]) <= frame:
				list.remove_at(i)
		if list.is_empty():
			_entity_effects.erase(id)
	if enemy_changed:
		_emit_enemy_scale_changed_if_changed()


func _prune_dead_nodes() -> void:
	for id: int in _groups.keys():
		if instance_from_id(id) == null:
			_groups.erase(id)
	for id: int in _entity_effects.keys():
		if instance_from_id(id) == null:
			_entity_effects.erase(id)


func _tick_scaled_timers(delta: float) -> void:
	var keep: Array[ScaledTimer] = []
	for scaled: ScaledTimer in _scaled_timers:
		var node := instance_from_id(scaled.node_id) as Node
		if node != null and scale_for(node) > 0.0:
			scaled.remaining -= delta * scale_for(node)
		if scaled.remaining > 0.0:
			keep.append(scaled)
		else:
			scaled.timeout.emit()
	_scaled_timers = keep


func _broadcast_time_effect(group: int, factor: float, seconds: float, source: StringName) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return  # solo server: nothing to broadcast to
	rpc("time_effect_applied", group, factor, seconds, source)


func _broadcast_entity(node: Node, factor: float, seconds: float, source: StringName) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return
	var world := GameState.world
	var path := node.get_path()
	if world != null and world.is_ancestor_of(node):
		path = world.get_path_to(node)
	rpc("entity_time_applied", path, factor, seconds, source)


func _resolve_world_path(path: NodePath) -> Node:
	if GameState.world != null:
		var found := GameState.world.get_node_or_null(path)
		if found != null:
			return found
	return get_node_or_null(path)


## Internal one-shot countdown; the signal returned by timer() lives on this.
## Stores the node by instance id so a freed node cannot keep the timer alive.
class ScaledTimer:
	extends RefCounted

	signal timeout

	var node_id: int = 0
	var remaining: float = 0.0
