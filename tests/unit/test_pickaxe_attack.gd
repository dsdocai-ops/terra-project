extends GutTest
## Tests for W2-A7's weapon base: the `WeaponAttack` hook routing in
## `WeaponController`, light / heavy / swap working for the Pickaxe, and its
## signature — the heavy cracks the ground in a line (SINKHOLE_SPEC section 7,
## Blades). Owned by weapons. Steps the state machine and timers by hand;
## TimeManager sources and leftover cracks are cleared after each.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const PICKAXE_PATH := "res://data/weapons/pickaxe.tres"
const PICKAXE_SCENE := "res://scenes/player/weapons/pickaxe.tscn"
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


# A test double that records which hooks the controller routes to.
class HookSpy extends WeaponAttack:
	var light_calls: Array[int] = []
	var heavy_charges: Array[float] = []
	var skill_calls: int = 0

	func light(step: int) -> void:
		light_calls.append(step)

	func heavy(charge: float) -> void:
		heavy_charges.append(charge)

	func skill() -> void:
		skill_calls += 1


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


func _cracks() -> Array[Node]:
	var found: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(&"ground_cracks"):
		found.append(node)
	return found


# --- data and scene -------------------------------------------------------------------------

func test_the_pickaxe_data_loads_with_a_three_step_combo_and_a_heavy() -> void:
	var pickaxe: WeaponData = load(PICKAXE_PATH) as WeaponData
	assert_not_null(pickaxe, "pickaxe.tres loads as WeaponData")
	assert_eq(pickaxe.light_combo.size(), 3, "a three-hit combo")
	assert_not_null(pickaxe.heavy, "a heavy")
	assert_not_null(pickaxe.skill, "the 300-degree sweep skill")


func test_the_pickaxe_attack_scene_instantiates() -> void:
	var scene: PackedScene = load(PICKAXE_SCENE) as PackedScene
	assert_not_null(scene, "%s loads" % PICKAXE_SCENE)
	var node := scene.instantiate() as PickaxeAttack
	assert_not_null(node, "and instantiates as a PickaxeAttack")
	if node != null:
		node.free()


# --- light, heavy and swap on the Pickaxe ---------------------------------------------------

func test_the_pickaxe_light_combo_steps_and_wraps() -> void:
	var pickaxe: WeaponData = load(PICKAXE_PATH) as WeaponData
	_weapons.equip(0, pickaxe)
	assert_eq(_weapons.take_light(), pickaxe.light_combo[0])
	assert_eq(_weapons.last_light_step, 0)
	assert_eq(_weapons.take_light(), pickaxe.light_combo[1])
	assert_eq(_weapons.last_light_step, 1)
	assert_eq(_weapons.take_light(), pickaxe.light_combo[2])
	assert_eq(_weapons.last_light_step, 2, "the finisher")
	assert_eq(_weapons.take_light(), pickaxe.light_combo[0], "and it wraps to step 0")


func test_the_pickaxe_heavy_is_the_ground_cracking_one() -> void:
	var pickaxe: WeaponData = load(PICKAXE_PATH) as WeaponData
	_weapons.equip(0, pickaxe)
	assert_eq(_weapons.take_heavy(), pickaxe.heavy)
	assert_gt(pickaxe.heavy.reach, pickaxe.light_combo[0].reach, "and out-reaches the light")
	assert_gt(pickaxe.heavy.knockback, pickaxe.light_combo[0].knockback)


func test_a_pickaxe_light_attack_turns_the_hitbox_live_for_its_active_window() -> void:
	_player.pending_attack = {"spec": _weapons.take_light(), "dir": Vector2.RIGHT, "charge": 0.0, "heavy": false}
	_player.state_machine.change_to(&"Attack")
	_tick(0.1)
	assert_eq(_state(), &"Attack")
	assert_true(_weapons._hitbox.active, "live through the active window")
	_tick(0.2)
	assert_false(_weapons._hitbox.active, "and off when the window closes")


func test_swap_away_from_the_pickaxe_and_back_respects_the_lockout() -> void:
	assert_eq(_active_weapon_id(), &"pickaxe", "the default slot 0 weapon is the Pickaxe")
	_weapons.take_light()
	assert_true(_weapons.swap(), "swaps to the other slot")
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


func _active_weapon_id() -> StringName:
	return _weapons.active_weapon().id


# --- the ground crack line ------------------------------------------------------------------

func test_the_pickaxe_heavy_emits_one_ground_crack_line() -> void:
	_press_heavy()
	_tick(0.8)
	_player.facing = Vector2.RIGHT
	_release_heavy()
	assert_eq(_state(), &"Attack", "setup: the heavy released")
	_tick(0.2)
	var cracks: Array[Node] = _cracks()
	assert_eq(cracks.size(), 1, "one crack line per heavy")
	if cracks.size() == 1:
		var crack := cracks[0] as GroundCrackLine
		assert_not_null(crack)
		var points: PackedVector2Array = crack.points()
		assert_eq(points.size(), GroundCrackLine.MARK_COUNT)
		assert_almost_eq(points[0].x, 0.0, 0.01, "starts at the strike origin")
		assert_almost_eq(points[0].y, 0.0, 0.01)
		var far: float = WeaponController.melee_reach((load(PICKAXE_PATH) as WeaponData).heavy, 1.0, true)
		assert_almost_eq(points[points.size() - 1].x, far, 0.01, "ends at the charged heavy's reach")
		assert_almost_eq(points[points.size() - 1].y, 0.0, 0.01, "ends on the swing line")
		assert_gt(crack.seconds_left(), 0.0, "and it is fading out")


func test_the_crack_length_tracks_the_charge_bucket() -> void:
	var heavy: AttackSpec = (load(PICKAXE_PATH) as WeaponData).heavy
	var tapped: GroundCrackLine = GroundCrackLine.spawn(_player, Vector2.ZERO, Vector2.RIGHT, WeaponController.melee_reach(heavy, 0.0, true))
	var full: GroundCrackLine = GroundCrackLine.spawn(_player, Vector2.ZERO, Vector2.RIGHT, WeaponController.melee_reach(heavy, 1.0, true))
	var tapped_far: float = tapped.points()[tapped.points().size() - 1].x
	var full_far: float = full.points()[full.points().size() - 1].x
	assert_almost_eq(tapped_far, heavy.reach, 0.01, "a tap cracks just the heavy's reach")
	assert_gt(full_far, tapped_far, "a full charge cracks further")
	assert_almost_eq(full_far, heavy.reach * 1.35, 0.01, "by the charge bucket's 35%")


func test_the_crack_points_stay_inside_the_jitter_corridor() -> void:
	var from := Vector2(11.0, -3.0)
	var dir := Vector2(0.6, 0.8)
	var length := 90.0
	var points: PackedVector2Array = GroundCrackLine.crack_points(from, dir, length)
	var across := Vector2(-dir.normalized().y, dir.normalized().x)
	var last_share: float = -1.0
	for point: Vector2 in points:
		var local := point - from
		var share: float = local.dot(dir.normalized())
		assert_gte(share, -0.01, "never behind the strike")
		assert_lte(share, length + 0.01, "never past the reach")
		assert_gte(share, last_share, "marching forward along the line")
		last_share = share
		assert_lte(absf(local.dot(across)), GroundCrackLine.MAX_JITTER_PX + 0.01, "inside the corridor")
	assert_almost_eq(points[0].x, from.x, 0.01, "the first mark is the origin")
	assert_almost_eq(points[0].y, from.y, 0.01)
	var last: Vector2 = points[points.size() - 1]
	var expected_last: Vector2 = from + dir.normalized() * length
	assert_almost_eq(last.x, expected_last.x, 0.01, "the last mark is the full reach")
	assert_almost_eq(last.y, expected_last.y, 0.01)


func test_a_spawned_crack_line_fades_out_and_frees_itself() -> void:
	var crack := GroundCrackLine.spawn(_player, Vector2.ZERO, Vector2.RIGHT, 60.0)
	crack.step(GroundCrackLine.LIFETIME_SECONDS - 0.1)
	assert_gt(crack.seconds_left(), 0.0, "still fading")
	assert_false(crack.is_queued_for_deletion())
	crack.step(0.2)
	assert_true(crack.is_queued_for_deletion(), "gone at the end of its life")


func test_a_light_attack_emits_no_crack() -> void:
	_player.pending_attack = {"spec": _weapons.take_light(), "dir": Vector2.RIGHT, "charge": 0.0, "heavy": false}
	_player.state_machine.change_to(&"Attack")
	_tick(0.2)
	assert_eq(_cracks().size(), 0, "only the heavy cracks the ground")


# --- the crack broadcast --------------------------------------------------------------------

func test_strike_ground_crack_spawns_the_local_crack() -> void:
	_weapons.strike_ground_crack(Vector2(4.0, 5.0), Vector2.RIGHT, 70.0)
	var cracks: Array[Node] = _cracks()
	assert_eq(cracks.size(), 1, "one local crack per strike")
	if cracks.size() == 1:
		var crack := cracks[0] as GroundCrackLine
		assert_not_null(crack)
		assert_almost_eq(crack.global_position.x, 4.0, 0.01, "at the strike origin")
		assert_almost_eq(crack.global_position.y, 5.0, 0.01)
		# The node sits at the strike origin, so its marks are the local geometry.
		var expected: PackedVector2Array = GroundCrackLine.crack_points(Vector2.ZERO, Vector2.RIGHT, 70.0)
		assert_eq(crack.points(), expected, "with the strike's own geometry")


func test_a_solo_host_forwards_no_crack() -> void:
	_weapons.strike_ground_crack(Vector2.ZERO, Vector2.RIGHT, 60.0)
	assert_eq(_weapons.cracks_forwarded, 0, "solo has nobody to tell, the local crack is all there is")


func test_the_crack_targets_are_every_peer_except_the_owner() -> void:
	assert_eq(WeaponController.crack_targets(1, [1, 5, 7] as Array[int]), [5, 7] as Array[int],
		"the owner already drew its own crack inside the hook")
	assert_eq(WeaponController.crack_targets(5, [5] as Array[int]), [] as Array[int],
		"an owner alone in the session has nobody to tell")
	assert_eq(WeaponController.crack_targets(1, [] as Array[int]), [] as Array[int], "an empty session targets nobody")


func test_the_crack_rpc_is_registered_unreliable_and_remote() -> void:
	var rpc: Dictionary = (_weapons.get_script() as Script).get_rpc_config() as Dictionary
	assert_true(rpc.has(&"_remote_ground_crack"), "the crack RPC is registered")
	assert_eq(rpc[&"_remote_ground_crack"]["transfer_mode"], MultiplayerPeer.TRANSFER_MODE_UNRELIABLE,
		"a dropped crack is a 0.7 s decal, not state")
	assert_false(rpc[&"_remote_ground_crack"]["call_local"], "the sender already drew its own crack")


func test_the_crack_rpc_refuses_a_direct_local_call() -> void:
	# The body validates `multiplayer.get_remote_sender_id()` first: a direct
	# local call reports sender 0 everywhere, so a peer cannot draw the host's
	# crack by calling the RPC on itself instead of receiving it.
	_weapons._remote_ground_crack(Vector2.ZERO, Vector2.RIGHT, 60.0)
	assert_eq(_cracks().size(), 0, "sender 0 is not the host's crack")
	assert_eq(_weapons.remote_cracks_received, 0, "and nothing was received")


# --- the WeaponAttack hook routing ----------------------------------------------------------

func _hook_spy_on(weapon: WeaponData) -> HookSpy:
	var spy := HookSpy.new()
	_weapons.add_child(spy)
	spy.weapons = _weapons
	spy.player = _player
	_weapons._attack_nodes[weapon.id] = spy
	return spy


func test_a_swing_routes_light_heavy_and_skill_to_the_attack_node() -> void:
	var pickaxe: WeaponData = load(PICKAXE_PATH) as WeaponData
	_weapons.equip(0, pickaxe)
	var spy := _hook_spy_on(pickaxe)
	_weapons.begin_swing(_weapons.take_light(), Vector2.RIGHT, 0.0, false)
	assert_eq(spy.light_calls, [0] as Array[int], "the light routes with its step")
	_weapons.begin_swing(_weapons.take_heavy(), Vector2.RIGHT, 0.65, true)
	assert_eq(spy.heavy_charges, [0.65] as Array[float], "the heavy routes with its charge")
	_weapons.begin_swing(pickaxe.skill, Vector2.RIGHT, 0.0, true)
	assert_eq(spy.skill_calls, 1, "the weapon skill routes to the skill hook")
	assert_eq(spy.heavy_charges.size(), 1, "and not to the heavy hook")


func test_the_pickaxe_attack_node_is_made_from_its_scene_on_first_swing() -> void:
	var pickaxe: WeaponData = load(PICKAXE_PATH) as WeaponData
	_weapons.equip(0, pickaxe)
	assert_false(_weapons._attack_nodes.has(pickaxe.id), "nothing made before the first swing")
	_weapons.begin_swing(_weapons.take_light(), Vector2.RIGHT, 0.0, false)
	var node: WeaponAttack = _weapons._attack_nodes.get(pickaxe.id) as WeaponAttack
	assert_not_null(node)
	assert_true(node is PickaxeAttack, "instanced from scenes/player/weapons/pickaxe.tscn")
	assert_eq(node.weapons, _weapons)
	assert_eq(node.player, _player)


func test_a_crossbow_swing_makes_its_own_attack_node_and_no_crack() -> void:
	var crossbow: WeaponData = load("res://data/weapons/crossbow.tres") as WeaponData
	_weapons.equip(0, crossbow)
	_weapons.begin_swing(crossbow.light_combo[0], Vector2.RIGHT, 0.0, false)
	var node: WeaponAttack = _weapons._attack_nodes.get(crossbow.id) as WeaponAttack
	assert_not_null(node, "a node exists for it")
	assert_true(node is CrossbowAttack, "instanced from scenes/player/weapons/crossbow.tscn")
	assert_eq(_cracks().size(), 0, "no pickaxe signature on a crossbow swing")


# --- the charged state ----------------------------------------------------------------------

func test_the_charged_state_is_reached_and_cleared_for_the_pickaxe() -> void:
	_press_heavy()
	_tick(0.05)
	assert_eq(_state(), &"HeavyCharge", "a heavy press enters the charged state")
	_tick(0.35)
	var charge: PlayerHeavyChargeState = _player.state_machine.current as PlayerHeavyChargeState
	assert_not_null(charge, "still charging")
	if charge != null:
		assert_almost_eq(charge.charge(), 0.4 / 0.8, 0.02, "the charge builds on the pickaxe's own 0.8 s")
	_tick(0.4)
	if charge != null:
		assert_true(charge.is_full(), "full at 0.8 s")
	_release_heavy()
	_tick(FRAME)
	assert_ne(_state(), &"HeavyCharge", "the release clears the charged state")
	assert_eq(_state(), &"Attack")
	_tick(0.7)
	assert_eq(_state(), &"Idle", "setup: the heavy's swing has played out")
	_press_heavy()
	_tick(0.05)
	var fresh: PlayerHeavyChargeState = _player.state_machine.current as PlayerHeavyChargeState
	assert_not_null(fresh, "a new hold charges again")
	if fresh != null:
		assert_almost_eq(fresh.charge(), 0.0, 0.01, "and starts from zero, nothing carried over")
