class_name ClassController
extends Node
## One player's class (SPEC-classes-characters "ClassController"): attaches the class
## passive when the class is set, attaches and detaches the affinity effect as the
## active weapon gains or loses the class's affinity (WeaponController's
## affinity_active_changed), and runs the Shift class skill with its own cooldown.
## Owned by classes-characters. Sync: host-authoritative. The passive and the
## affinity are EffectHost attachments, so they attach on the host only. The skill
## runs on the host: a client's press goes to the host with ask_class_skill, and the
## host checks the sender owns the player before it runs the skill. `class_resource`
## is host-owned and not yet replicated (W5-G9c waits on D-G6-1).

const REFUSE_NONE: StringName = &""
const REFUSE_NOT_HOST: StringName = &"not_host"
const REFUSE_NOT_OWNER: StringName = &"not_owner"
const REFUSE_NO_CLASS: StringName = &"no_class"
const REFUSE_COOLING: StringName = &"cooling"
## Joins the class id into the affinity effect's id, so the passive and the affinity
## are two attachments of one class.
const AFFINITY_SUFFIX: String = "_affinity"
const SKILL_NODE_NAME: String = "ClassSkill"

## The class the player picked, or null before a pick. Set with set_class().
var class_data: ClassData = null
## The class resource ("scrap", "souls", or Rage). Host-owned, read by the HUD.
var class_resource: float = 0.0
## The live Shift skill for the class, or null with no class.
var skill: ClassSkill = null
## Why the last request_class_skill was refused, or REFUSE_NONE after a use.
var last_refusal: StringName = REFUSE_NONE

var _player: Player = null
var _weapons: WeaponController = null
## The effect sources for the passive and the affinity. Each wraps one effect script
## in a ContentData so it goes through EffectHost.add, and its id is what remove() keys on.
var _passive_source: ContentData = null
var _affinity_source: ContentData = null


func _ready() -> void:
	_player = get_parent() as Player
	if _player != null:
		_weapons = _player.get_node_or_null("WeaponController") as WeaponController
	if _weapons != null:
		_weapons.affinity_active_changed.connect(_on_affinity_changed)
	if class_data != null:
		_start_class()


func _physics_process(delta: float) -> void:
	tick(delta)


## Runs the skill's cooldown for `delta` seconds. Called from _physics_process; tests
## call it directly.
func tick(delta: float) -> void:
	if skill != null:
		skill.tick(delta)


## Sets the class the player picked: detaches the old class's effects and skill, then
## attaches the new passive, makes its skill and hands its affinity list to the
## weapons. Null clears the class.
func set_class(data: ClassData) -> void:
	_clear_class()
	class_data = data
	if class_data != null and is_node_ready():
		_start_class()


## Runs the class skill if the host allows it: a class is set, the skill is ready and
## the caller is the host. Starts the cooldown, announces the use once on
## Events.class_skill_used and returns true. A refusal returns false and sets
## last_refusal. Host only.
func request_class_skill() -> bool:
	last_refusal = REFUSE_NONE
	if not multiplayer.is_server():
		last_refusal = REFUSE_NOT_HOST
		return false
	if skill == null:
		last_refusal = REFUSE_NO_CLASS
		return false
	if not skill.is_ready():
		last_refusal = REFUSE_COOLING
		return false
	skill.use()
	Events.class_skill_used.emit(_player)
	return true


## What a player's own input calls. On the host it runs the skill at once. On a client
## it sends the request to the host, which checks the sender and runs it, so the
## return value means "sent", not "ran".
func ask_class_skill() -> bool:
	if multiplayer.is_server():
		return request_class_skill()
	_remote_request_class_skill.rpc_id(NetworkManager.HOST_PEER_ID)
	return true


## Client -> host. Refused unless the sender is the peer that owns this player; a
## request with no sender (a local call) is refused too.
@rpc("any_peer", "call_remote", "reliable")
func _remote_request_class_skill() -> void:
	if _player == null or multiplayer.get_remote_sender_id() != _player.peer_id:
		last_refusal = REFUSE_NOT_OWNER
		return
	request_class_skill()


## Attaches the passive, makes the Shift skill and sets the affinity ids on the weapons.
## The affinity ids announce the active weapon's state, so an affinity that applies at
## once attaches here.
func _start_class() -> void:
	if class_data.passive_effect != null:
		_passive_source = _effect_source(class_data.passive_effect, class_data.id)
		_attach(_passive_source)
	skill = _make_skill()
	if _weapons != null:
		_weapons.set_affinity_ids(class_data.affinity_weapon_ids)


## Detaches what the current class attached, frees its skill and clears the affinity
## ids. Called before a new class is set, and with null.
func _clear_class() -> void:
	_detach(_affinity_source)
	_detach(_passive_source)
	_free_skill()
	_passive_source = null
	_affinity_source = null
	if _weapons != null:
		var none: Array[StringName] = []
		_weapons.set_affinity_ids(none)


## WeaponController.affinity_active_changed: the affinity effect attaches while an
## affinity weapon is active and detaches when it is not.
func _on_affinity_changed(active: bool) -> void:
	if not active or class_data == null or class_data.affinity_effect == null:
		_detach(_affinity_source)
		return
	_affinity_source = _effect_source(class_data.affinity_effect, StringName(String(class_data.id) + AFFINITY_SUFFIX))
	_attach(_affinity_source)


## Host only. Adds `source`'s effect to the player's EffectHost unless it is already there.
func _attach(source: ContentData) -> void:
	if not multiplayer.is_server():
		return
	var host := _effect_host()
	if host == null:
		push_warning("[class-controller] %s has no EffectHost, %s is not attached" % [name, source.id])
		return
	if not host.has_effect(source.id):
		host.add(source)


## Removes `source`'s effect from the player's EffectHost when it is attached.
func _detach(source: ContentData) -> void:
	if source == null:
		return
	var host := _effect_host()
	if host != null and host.has_effect(source.id):
		host.remove(source)


## A ContentData that carries one effect script, so a class effect goes through
## EffectHost.add like every other effect. Built here, so the class data keeps the
## spec's fields only.
func _effect_source(script: GDScript, source_id: StringName) -> ContentData:
	var source := ContentData.new()
	source.id = source_id
	source.effect_script = script
	return source


## The player's EffectHost, or null when the player has none.
func _effect_host() -> EffectHost:
	if _player == null:
		return null
	return _player.get_node_or_null(NodePath(EffectHost.NODE_NAME)) as EffectHost


## Instances the class's skill scene under this controller, with the player as its
## time node. Null when the class has no skill.
func _make_skill() -> ClassSkill:
	_free_skill()
	if class_data.class_skill == null:
		return null
	var made: Node = class_data.class_skill.instantiate()
	if not (made is ClassSkill):
		push_warning("[class-controller] %s's class_skill is not a ClassSkill" % class_data.id)
		made.free()
		return null
	var skill_node := made as ClassSkill
	skill_node.name = SKILL_NODE_NAME
	skill_node.timed_node = _player
	add_child(skill_node)
	return skill_node


func _free_skill() -> void:
	if skill == null:
		return
	remove_child(skill)
	skill.free()
	skill = null
