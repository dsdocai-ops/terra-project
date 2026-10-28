extends GutTest
## Tests for W2-A7's Crossbow: its attack node on the projectile base
## (`scenes/player/weapons/crossbow.tscn`), light / heavy / swap working, and
## the charged bolt — a charged heavy scales the bolt it fires and the charged
## state is reached and cleared on the crossbow's own 0.9 s (SPEC-weapons
## "Charged attacks"). Owned by weapons. Steps the state machine and timers by
## hand; TimeManager sources are cleared after each. Named-method callbacks only.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CROSSBOW_PATH := "res://data/weapons/crossbow.tres"
const CROSSBOW_SCENE := "res://scenes/player/weapons/crossbow.tscn"
const PICKAXE_PATH := "res://data/weapons/pickaxe.tres"
const FRAME := 1.0 / 60.0

var _player: Player
var _controller: AttackController
var _weapons: WeaponController
var _swaps: Array[int] = []


func before_each() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.position = Vector2.ZERO
	_controller = _player.get_node("AttackController") as AttackController
	_weapons = _player.get_node("WeaponController") as WeaponController
	_swaps.clear()
	_weapons.weapon_changed.connect(_on_weapon_changed)


func after_each() -> void:
	if _weapons.weapon_changed.is_connected(_on_weapon_changed):
		_weapons.weapon_changed.disconnect(_on_weapon_changed)
	TimeManager.clear_source(TimeManager.HIT_STOP_SOURCE)
	TimeManager.clear_source(&"test")
	for crack: Node in get_tree().get_nodes_in_group(&"ground_cracks"):
		crack.free()


func _on_weapon_changed(slot: int, _weapon: WeaponData) -> void:
	_swaps.append(slot)


func _tick(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0:
		var dt: float = minf(FRAME, remaining)
		_controller.tick_buffer(dt)
		_player.state_machine.physics_update(dt)
		_weapons._physics_process(dt)
		_player._tick_combat_timers(dt)
		remaining -= dt


func _state() -> StringName:
	return _player.state_machine.current_name()


func _press_heavy() -> void:
	_controller.apply(AttackController.Kind.HEAVY_PRESS, Vector2.RIGHT, 0.0)


func _release_heavy() -> void:
	_controller.release_heavy()


func _crossbow() -> WeaponData:
	return load(CROSSBOW_PATH) as WeaponData


func _active_weapon_id() -> StringName:
	return _weapons.active_weapon().id


func _crossbow_node() -> WeaponAttack:
	return _weapons._attack_nodes.get(&"crossbow") as WeaponAttack


# --- data and scene -------------------------------------------------------------------------

func test_the_crossbow_data_loads_with_light_heavy_and_skill() -> void:
	var crossbow: WeaponData = _crossbow()
	assert_not_null(crossbow, "crossbow.tres loads as WeaponData")
	assert_eq(crossbow.light_combo.size(), 1, "a single quick bolt per light press")
	assert_not_null(crossbow.heavy, "a heavy")
	assert_not_null(crossbow.skill, "the pierce-8 skill bolt")
	assert_almost_eq(crossbow.heavy_charge_seconds, 0.9, 0.001, "its own charge time")


func test_the_crossbow_heavy_is_the_piercing_charged_bolt() -> void:
	var crossbow: WeaponData = _crossbow()
	assert_eq(crossbow.light_combo[0].shape, AttackSpec.Shape.PROJECTILE, "the light is a shot")
	assert_eq(crossbow.heavy.shape, AttackSpec.Shape.PROJECTILE, "the heavy is a shot")
	assert_gt(crossbow.heavy.pierce, crossbow.light_combo[0].pierce, "the charged shot pierces deeper")
	assert_gt(crossbow.skill.pierce, crossbow.heavy.pierce, "and the skill deepest")


func test_the_crossbow_attack_scene_instantiates() -> void:
	var scene: PackedScene = load(CROSSBOW_SCENE) as PackedScene
	assert_not_null(scene, "%s loads" % CROSSBOW_SCENE)
	var node := scene.instantiate() as CrossbowAttack
	assert_not_null(node, "and instantiates as a CrossbowAttack")
	if node != null:
		node.free()


# --- light, heavy and swap on the Crossbow ---------------------------------------------------

func test_the_crossbow_light_combo_steps_and_wraps() -> void:
	var crossbow: WeaponData = _crossbow()
	_weapons.equip(0, crossbow)
	assert_eq(_weapons.take_light(), crossbow.light_combo[0])
	assert_eq(_weapons.last_light_step, 0)
	assert_eq(_weapons.take_light(), crossbow.light_combo[0], "one step, so it wraps to itself")


func test_the_crossbow_heavy_is_what_take_heavy_hands_back() -> void:
	var crossbow: WeaponData = _crossbow()
	_weapons.equip(0, crossbow)
	assert_eq(_weapons.take_heavy(), crossbow.heavy)


func test_a_crossbow_shot_builds_a_ranged_projectile_hit() -> void:
	var crossbow: WeaponData = _crossbow()
	_weapons.equip(0, crossbow)
	var light_hit: HitInfo = _weapons.build_hit(crossbow.light_combo[0], Vector2.RIGHT, 0.0, false)
	assert_true(light_hit.is_projectile, "the light is a projectile shot")
	assert_true(light_hit.tags.has(&"crossbow"), "tagged by its weapon")
	assert_true(light_hit.tags.has(&"ranged"), "and ranged, not melee")
	var heavy_hit: HitInfo = _weapons.build_hit(crossbow.heavy, Vector2.RIGHT, 1.0, true)
	assert_true(heavy_hit.is_heavy, "the heavy swings heavy")
	assert_true(heavy_hit.is_projectile, "and is a shot too")
	assert_gt(heavy_hit.base_damage, light_hit.base_damage, "the charged heavy out-damages the light")


func test_swap_to_the_crossbow_and_back_respects_the_lockout() -> void:
	assert_eq(_active_weapon_id(), &"pickaxe", "the default slot 0 weapon is the Pickaxe")
	assert_true(_weapons.swap(), "swaps to the crossbow slot")
	assert_eq(_active_weapon_id(), &"crossbow")
	assert_eq(_swaps, [1] as Array[int])
	assert_false(_weapons.can_swap(), "the 0.2 s lockout is running")
	_weapons.take_light()
	_tick(0.25)
	assert_true(_weapons.can_swap(), "lockout over")
	assert_true(_weapons.swap(), "swaps back")
	assert_eq(_active_weapon_id(), &"pickaxe")
	assert_eq(_weapons.combo_step, 0, "a swap resets the combo")
	assert_eq(_weapons.last_light_step, 0)


func test_the_crossbow_attack_node_is_made_from_its_scene_on_first_swing() -> void:
	var crossbow: WeaponData = _crossbow()
	_weapons.equip(0, crossbow)
	assert_false(_weapons._attack_nodes.has(crossbow.id), "nothing made before the first swing")
	_weapons.begin_swing(crossbow.light_combo[0], Vector2.RIGHT, 0.0, false)
	var node: WeaponAttack = _crossbow_node()
	assert_not_null(node, "made on the first swing")
	assert_true(node is CrossbowAttack, "instanced from scenes/player/weapons/crossbow.tscn")
	assert_eq(node.weapons, _weapons)
	assert_eq(node.player, _player)


# --- the charged bolt: heavy(charge) scales the shot's size ----------------------------------

func test_the_charged_heavy_scales_the_bolt_and_a_light_resets_it() -> void:
	var crossbow: WeaponData = _crossbow()
	_weapons.equip(0, crossbow)
	_weapons.begin_swing(crossbow.light_combo[0], Vector2.RIGHT, 0.0, false)
	var node: WeaponAttack = _crossbow_node()
	assert_not_null(node, "setup: the attack node exists")
	if node == null:
		return
	assert_almost_eq(node.shot_scale, 1.0, 0.001, "a light bolt is the base size")
	_weapons.begin_swing(crossbow.heavy, Vector2.RIGHT, 1.0, true)
	assert_almost_eq(node.shot_scale, 1.0 + CrossbowAttack.FULL_CHARGE_SCALE_BONUS, 0.001,
		"a full charge makes the bolt bigger")
	_weapons.begin_swing(crossbow.heavy, Vector2.RIGHT, 0.5, true)
	assert_almost_eq(node.shot_scale, 1.0 + 0.5 * CrossbowAttack.FULL_CHARGE_SCALE_BONUS, 0.001,
		"the scale tracks the charge linearly")
	_weapons.begin_swing(crossbow.light_combo[0], Vector2.RIGHT, 0.0, false)
	assert_almost_eq(node.shot_scale, 1.0, 0.001, "a light resets it")
	_weapons.begin_swing(crossbow.skill, Vector2.RIGHT, 0.0, true)
	assert_almost_eq(node.shot_scale, 1.0, 0.001, "the skill bolt is the base size")


# --- the charged state -----------------------------------------------------------------------

func test_the_charged_state_is_reached_and_cleared_for_the_crossbow() -> void:
	_weapons.equip(0, _crossbow())
	_press_heavy()
	_tick(0.05)
	assert_eq(_state(), &"HeavyCharge", "a heavy press enters the charged state")
	_tick(0.4)
	var charge: PlayerHeavyChargeState = _player.state_machine.current as PlayerHeavyChargeState
	assert_not_null(charge, "still charging")
	if charge != null:
		assert_almost_eq(charge.charge(), 0.45 / 0.9, 0.02, "the charge builds on the crossbow's own 0.9 s")
	_tick(0.45)
	if charge != null:
		assert_true(charge.is_full(), "full at 0.9 s — slower than the pickaxe's 0.8")
	_release_heavy()
	_tick(FRAME)
	assert_ne(_state(), &"HeavyCharge", "the release clears the charged state")
	assert_eq(_state(), &"Attack")
	_tick(0.6)
	assert_eq(_state(), &"Idle", "setup: the heavy's swing has played out")
	_press_heavy()
	_tick(0.05)
	var fresh: PlayerHeavyChargeState = _player.state_machine.current as PlayerHeavyChargeState
	assert_not_null(fresh, "a new hold charges again")
	if fresh != null:
		assert_almost_eq(fresh.charge(), 0.0, 0.01, "and starts from zero, nothing carried over")
