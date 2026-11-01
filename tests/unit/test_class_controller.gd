extends GutTest
## Unit checks for ClassController (SPEC-classes-characters "ClassController"): the
## passive attaches when the class is set or the controller enters the tree, the
## affinity attaches on equip and detaches on unequip, the Shift skill is refused
## while cooling and runs once per use, class_skill_used is emitted once per use,
## a client cannot run the skill, and class_resource is exposed. Owned by
## classes-characters. Sync: host-authoritative. Runs on the real player scene with
## its EffectHost (EffectHostPlayer), so effects attach as they do in a run. The
## class effects are fixtures (FixtureClassPassive, FixtureClassSkill), since the
## real passives and skills are W5-G10b and G10c. The TimeManager source is cleared
## after each test.

const TIME_SOURCE: StringName = &"test_class_slow"
const CLIENT_PORT: int = 7819
const CLASS_ID: StringName = &"fixture_warrior"
const AFFINITY_ID: StringName = &"fixture_warrior_affinity"
const AFFINITY_WEAPON_ID: StringName = &"lantern_staff"
const PLAIN_WEAPON_ID: StringName = &"fixture_plain_blade"
const SKILL_COOLDOWN: float = 6.0

var _player: Player
var _controller: ClassController


func before_each() -> void:
	_player = EffectHostPlayer.spawn(self)
	_controller = _player.get_node("ClassController") as ClassController


func after_each() -> void:
	TimeManager.clear_source(TIME_SOURCE)
	if is_instance_valid(_player):
		_player.free()


func _host() -> EffectHost:
	return EffectHostPlayer.install(_player)


func _weapon(id: StringName) -> WeaponData:
	var data := WeaponData.new()
	data.id = id
	return data


func _skill_scene() -> PackedScene:
	var packed := PackedScene.new()
	var skill := FixtureClassSkill.new()
	skill.cooldown_seconds = SKILL_COOLDOWN
	packed.pack(skill)
	skill.free()
	return packed


## A fixture class: one affinity weapon, a passive and an affinity effect that are
## both fixtures, and a fixture Shift skill.
func _class_data() -> ClassData:
	var data := ClassData.new()
	data.id = CLASS_ID
	var ids: Array[StringName] = [AFFINITY_WEAPON_ID]
	data.affinity_weapon_ids = ids
	data.passive_effect = FixtureClassPassive
	data.affinity_effect = FixtureClassPassive
	data.class_skill = _skill_scene()
	return data


func _skill() -> FixtureClassSkill:
	return _controller.skill as FixtureClassSkill


func test_the_passive_attaches_when_the_class_is_set() -> void:
	_controller.set_class(_class_data())
	assert_true(_host().has_effect(CLASS_ID), "the passive is attached under the class id")
	assert_true(_host().get_effect(CLASS_ID).is_attached())


func test_the_passive_attaches_on_ready_when_the_class_is_already_set() -> void:
	# A controller built with its class in place attaches the passive when it enters
	# the tree, with no set_class call after that.
	var host := _host()
	_player.remove_child(_controller)
	_controller.free()
	var fresh := ClassController.new()
	fresh.class_data = _class_data()
	_player.add_child(fresh)
	_controller = fresh
	assert_true(host.has_effect(CLASS_ID), "_ready attaches the passive of the class already set")


func test_the_affinity_attaches_on_equip_and_detaches_on_unequip() -> void:
	_controller.set_class(_class_data())
	var weapons := _player.get_node("WeaponController") as WeaponController
	weapons.equip(0, _weapon(AFFINITY_WEAPON_ID))
	assert_true(_host().has_effect(AFFINITY_ID), "equipping an affinity weapon attaches the affinity")
	weapons.equip(0, null)
	assert_false(_host().has_effect(AFFINITY_ID), "unequipping it detaches the affinity")
	assert_true(_host().has_effect(CLASS_ID), "the passive stays on when the affinity weapon goes")


func test_a_weapon_off_the_affinity_list_attaches_no_affinity() -> void:
	_controller.set_class(_class_data())
	var weapons := _player.get_node("WeaponController") as WeaponController
	weapons.equip(0, _weapon(PLAIN_WEAPON_ID))
	assert_false(_host().has_effect(AFFINITY_ID))


func test_changing_the_class_detaches_the_old_passive_and_affinity() -> void:
	_controller.set_class(_class_data())
	var weapons := _player.get_node("WeaponController") as WeaponController
	weapons.equip(0, _weapon(AFFINITY_WEAPON_ID))
	_controller.set_class(null)
	assert_false(_host().has_effect(CLASS_ID), "clearing the class detaches its passive")
	assert_false(_host().has_effect(AFFINITY_ID), "clearing the class detaches its affinity")


func test_a_skill_request_with_no_class_is_refused() -> void:
	assert_false(_controller.request_class_skill())
	assert_eq(_controller.last_refusal, ClassController.REFUSE_NO_CLASS)


func test_a_skill_request_is_refused_while_cooling() -> void:
	_controller.set_class(_class_data())
	assert_true(_controller.request_class_skill())
	assert_false(_controller.request_class_skill())
	assert_eq(_controller.last_refusal, ClassController.REFUSE_COOLING)
	assert_eq(_skill().performs, 1, "a refused request performs nothing")


func test_the_skill_is_ready_again_once_its_cooldown_has_run() -> void:
	_controller.set_class(_class_data())
	_controller.request_class_skill()
	_controller.tick(SKILL_COOLDOWN)
	assert_true(_controller.request_class_skill(), "the skill runs again after its cooldown")
	assert_eq(_skill().performs, 2)


func test_tick_with_no_class_runs_nothing_and_does_not_crash() -> void:
	# The controller ticks every physics frame, including on a player with no class.
	_controller.tick(1.0)
	assert_null(_controller.skill, "no class, so no skill to tick")
	assert_push_warning_count(0, "a tick with no class is quiet")


func test_the_skill_cooldown_runs_in_time_manager_scaled_time() -> void:
	_controller.set_class(_class_data())
	TimeManager.set_entity_scale(_player, 0.5, 10.0, TIME_SOURCE)
	_controller.request_class_skill()
	_controller.tick(2.0)
	assert_almost_eq(_skill().cooldown_left(), SKILL_COOLDOWN - 1.0, 0.0001,
		"the controller ticks the skill in the player's time, so 2 s at half speed is 1 s")


func test_class_skill_used_is_emitted_once_per_use() -> void:
	_controller.set_class(_class_data())
	watch_signals(Events)
	_controller.request_class_skill()
	_controller.request_class_skill()
	assert_signal_emit_count(Events, "class_skill_used", 1,
		"one use emits once, and the refused second request emits nothing")


func test_a_client_runs_no_skill_and_attaches_no_passive() -> void:
	# Swap in a client API for this test only, as test_ability_controller.gd does, so
	# the host guard in request_class_skill and the host guard in _attach are the ones
	# that refuse the request and the attach.
	var default_api: MultiplayerAPI = get_multiplayer()
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", CLIENT_PORT), OK, "the client peer opens")
	var client_api := SceneMultiplayer.new()
	client_api.multiplayer_peer = client_peer
	get_tree().set_multiplayer(client_api, get_path())
	_controller.set_class(_class_data())
	watch_signals(Events)
	assert_false(_controller.request_class_skill())
	assert_eq(_controller.last_refusal, ClassController.REFUSE_NOT_HOST)
	assert_eq(_skill().performs, 0)
	assert_eq(_skill().cooldown_left(), 0.0, "a refused client request starts no cooldown")
	assert_signal_not_emitted(Events, "class_skill_used")
	assert_false(_host().has_effect(CLASS_ID), "a client attaches no passive")
	get_tree().set_multiplayer(default_api, get_path())
	client_peer.close()


func test_ask_on_the_host_runs_the_skill_at_once() -> void:
	_controller.set_class(_class_data())
	assert_true(_controller.ask_class_skill())
	assert_eq(_skill().performs, 1, "the host's own press runs the skill without an RPC")


func test_swapping_between_two_affinity_weapons_keeps_one_affinity() -> void:
	_controller.set_class(_class_data())
	var weapons := _player.get_node("WeaponController") as WeaponController
	weapons.equip(0, _weapon(AFFINITY_WEAPON_ID))
	weapons.equip(1, _weapon(AFFINITY_WEAPON_ID))
	weapons.select_slot(1)
	assert_eq(_host().effect_count(), 2, "the passive and one affinity, not a second affinity")
	assert_true(_host().has_effect(AFFINITY_ID))
	assert_push_warning_count(0, "a second attach of the affinity is skipped, not refused by the host")


func test_an_affinity_weapon_with_no_class_attaches_nothing() -> void:
	# The weapons can hold an affinity list with no class behind it (the weapon tests
	# set one directly), so the signal can announce true with no class set.
	var weapons := _player.get_node("WeaponController") as WeaponController
	var ids: Array[StringName] = [AFFINITY_WEAPON_ID]
	weapons.set_affinity_ids(ids)
	weapons.equip(0, _weapon(AFFINITY_WEAPON_ID))
	assert_eq(_host().effect_count(), 0, "no class, so no affinity effect and no error")


func test_a_class_without_an_affinity_effect_attaches_no_affinity() -> void:
	var data := _class_data()
	data.affinity_effect = null
	_controller.set_class(data)
	var weapons := _player.get_node("WeaponController") as WeaponController
	weapons.equip(0, _weapon(AFFINITY_WEAPON_ID))
	assert_false(_host().has_effect(AFFINITY_ID))
	assert_push_warning_count(0, "a class with no affinity effect is skipped quietly")


func test_a_class_without_a_passive_attaches_no_passive() -> void:
	var data := _class_data()
	data.passive_effect = null
	_controller.set_class(data)
	assert_eq(_host().effect_count(), 0, "no passive effect, so nothing attaches")
	assert_push_warning_count(0, "a class with no passive is skipped quietly")


func test_a_class_with_no_skill_scene_refuses_the_skill_as_no_class() -> void:
	var data := _class_data()
	data.class_skill = null
	_controller.set_class(data)
	assert_null(_controller.skill, "a class with no skill scene has no skill node")
	assert_false(_controller.request_class_skill())
	assert_eq(_controller.last_refusal, ClassController.REFUSE_NO_CLASS)


func test_clearing_a_class_that_never_attached_is_quiet() -> void:
	# The affinity source is made on the first affinity and the passive on the first
	# class, so a clear after an unequip still reaches a source that is not attached.
	_controller.set_class(_class_data())
	var weapons := _player.get_node("WeaponController") as WeaponController
	weapons.equip(0, _weapon(AFFINITY_WEAPON_ID))
	weapons.equip(0, null)
	_controller.set_class(null)
	assert_eq(_host().effect_count(), 0, "a clear detaches what is left and leaves none behind")
	assert_push_warning_count(0, "a detach of an effect already off the host is skipped quietly")


func test_a_controller_with_no_player_warns_once_and_does_not_crash() -> void:
	# A controller under a plain node, with no Player and no EffectHost: the passive
	# cannot attach, and the one warning says so.
	var bare := Node.new()
	add_child_autofree(bare)
	var controller := ClassController.new()
	bare.add_child(controller)
	controller.set_class(_class_data())
	assert_not_null(controller.skill, "the skill still exists without a player")
	assert_push_warning_count(1, "the passive attach warns once that there is no EffectHost")


func test_clearing_a_class_with_no_ehost_is_quiet() -> void:
	# Set on a controller with no Player and no EffectHost, the passive attach warns once.
	# The clear then finds no host to detach from, and must do nothing more than that.
	var bare := Node.new()
	add_child_autofree(bare)
	var controller := ClassController.new()
	bare.add_child(controller)
	controller.set_class(_class_data())
	controller.set_class(null)
	assert_null(controller.skill, "clearing the class frees its skill")
	assert_push_warning_count(1, "the clear detaches with no host and adds no warning")


func test_a_remote_request_with_no_player_is_refused_as_not_owner() -> void:
	var bare := Node.new()
	add_child_autofree(bare)
	var controller := ClassController.new()
	bare.add_child(controller)
	controller._remote_request_class_skill()
	assert_eq(controller.last_refusal, ClassController.REFUSE_NOT_OWNER, "a request for no player is refused")


func test_a_class_skill_scene_that_is_not_a_class_skill_warns_and_has_no_skill() -> void:
	var data := _class_data()
	var packed := PackedScene.new()
	var plain := Node.new()
	packed.pack(plain)
	plain.free()
	data.class_skill = packed
	_controller.set_class(data)
	assert_null(_controller.skill, "a scene that is not a ClassSkill makes no skill")
	assert_push_warning_count(1, "the bad skill scene is reported once")


func test_set_class_before_the_controller_is_ready_waits_for_ready() -> void:
	# Set before the controller is in the tree, nothing attaches or starts until _ready.
	var bare := Node.new()
	add_child_autofree(bare)
	var controller := ClassController.new()
	controller.set_class(_class_data())
	assert_null(controller.skill, "no skill is made before the controller is ready")
	assert_push_warning_count(0, "nothing attaches before the controller is ready")
	bare.add_child(controller)
	assert_not_null(controller.skill, "_ready starts the class it was given")
	assert_push_warning_count(1, "the start after ready finds no EffectHost, once")


func test_class_resource_is_exposed_and_starts_at_zero() -> void:
	assert_eq(_controller.class_resource, 0.0, "a class resource starts at zero")
	_controller.class_resource = 35.0
	assert_eq(_controller.class_resource, 35.0, "the value reads back")
