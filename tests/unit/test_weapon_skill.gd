extends GutTest
## Tests for the perfect-dodge weapon skill (SPEC-combat-core "Attack input
## layer", combat v2 C4): the skill fires only inside the window, consumes it,
## respects its cooldown (in TimeManager-scaled time), and a heavy press outside
## the window charges a heavy as before. Also the perfect-dodge feedback and the
## once-per-dodge `player_dodged` emission. Owned by combat-core. Steps the
## state machine and timers by hand; TimeManager sources are cleared after each.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FRAME := 1.0 / 60.0

var _player: Player
var _controller: AttackController
var _weapons: WeaponController
var _dodges: Array[bool] = []


func before_each() -> void:
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.position = Vector2.ZERO
	_controller = _player.get_node("AttackController") as AttackController
	_weapons = _player.get_node("WeaponController") as WeaponController
	_dodges.clear()
	Events.player_dodged.connect(_on_player_dodged)


func after_each() -> void:
	if Events.player_dodged.is_connected(_on_player_dodged):
		Events.player_dodged.disconnect(_on_player_dodged)
	TimeManager.clear_source(TimeManager.HIT_STOP_SOURCE)
	TimeManager.clear_source(&"test")


func _on_player_dodged(_who: Player, perfect: bool) -> void:
	_dodges.append(perfect)


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


# --- data --------------------------------------------------------------------------

func test_pickaxe_and_crossbow_carry_a_skill_with_its_own_shape() -> void:
	var pickaxe: WeaponData = load("res://data/weapons/pickaxe.tres") as WeaponData
	assert_not_null(pickaxe.skill)
	assert_eq(pickaxe.skill_cooldown_seconds, 6.0)
	assert_gt(pickaxe.skill.base_damage, pickaxe.heavy.base_damage, "a stronger heavy")
	assert_true(pickaxe.skill.shape != pickaxe.heavy.shape or pickaxe.skill.arc_degrees != pickaxe.heavy.arc_degrees, "a distinct shape")
	var crossbow: WeaponData = load("res://data/weapons/crossbow.tres") as WeaponData
	assert_not_null(crossbow.skill)
	assert_gt(crossbow.skill.base_damage, crossbow.heavy.base_damage)
	assert_gt(crossbow.skill.pierce, crossbow.heavy.pierce, "pierces further than the charged bolt")
	assert_eq(crossbow.skill_cooldown_seconds, 6.0)


# --- the window --------------------------------------------------------------------------

func test_the_skill_fires_only_inside_the_perfect_dodge_window() -> void:
	_press_heavy()
	assert_eq(_state(), &"HeavyCharge", "no window: a plain heavy charge")
	assert_eq(_weapons.skill_cooldown_left(), 0.0, "and the skill was not spent")
	_controller.apply(AttackController.Kind.HEAVY, Vector2.RIGHT, 0.0)
	_tick(0.8)
	assert_eq(_state(), &"Idle")
	_player.open_perfect_dodge_window()
	_press_heavy()
	assert_eq(_state(), &"Attack", "inside the window the press fires the skill")
	assert_eq(_player.pending_attack["spec"], _weapons.active_weapon().skill)
	assert_true(_player.pending_attack["heavy"], "a heavy-class attack")
	assert_gt(_weapons.skill_cooldown_left(), 0.0)


func test_firing_the_skill_consumes_the_window() -> void:
	_player.open_perfect_dodge_window()
	assert_true(_player.is_perfect_dodge_window())
	_press_heavy()
	assert_false(_player.is_perfect_dodge_window(), "the window is spent")


func test_the_window_closes_by_itself_after_half_a_second() -> void:
	_player.open_perfect_dodge_window()
	_tick(0.45)
	assert_true(_player.is_perfect_dodge_window())
	_tick(0.1)
	assert_false(_player.is_perfect_dodge_window())
	_press_heavy()
	assert_eq(_state(), &"HeavyCharge", "late: a plain heavy")


func test_the_cooldown_blocks_a_second_fire() -> void:
	_player.open_perfect_dodge_window()
	_press_heavy()
	_tick(1.0)
	assert_eq(_state(), &"Idle", "setup: the skill attack ended")
	_player.open_perfect_dodge_window()
	_press_heavy()
	assert_eq(_state(), &"HeavyCharge", "on cooldown: a normal heavy happens")
	assert_true(_player.is_perfect_dodge_window(), "and the window was not consumed")
	_controller.apply(AttackController.Kind.HEAVY, Vector2.RIGHT, 0.0)
	_tick(1.0)


func test_the_skill_is_ready_again_after_six_seconds() -> void:
	_player.open_perfect_dodge_window()
	_press_heavy()
	assert_false(_weapons.skill_ready())
	_tick(5.9)
	assert_false(_weapons.skill_ready(), "not at 5.9 s")
	_tick(0.2)
	assert_true(_weapons.skill_ready(), "ready after 6 s")
	_player.open_perfect_dodge_window()
	_press_heavy()
	assert_eq(_state(), &"Attack", "and it fires again")


func test_the_cooldown_runs_in_timemanager_scaled_time() -> void:
	_player.open_perfect_dodge_window()
	_press_heavy()
	TimeManager.set_entity_scale(_player, 0.0, 600.0, &"test")
	_weapons._physics_process(10.0)
	assert_almost_eq(_weapons.skill_cooldown_left(), 6.0, 0.001, "a time stop holds the cooldown")
	TimeManager.clear_source(&"test")
	TimeManager.set_entity_scale(_player, 0.5, 600.0, &"test")
	_weapons._physics_process(2.0)
	assert_almost_eq(_weapons.skill_cooldown_left(), 5.0, 0.001, "half speed counts down half as fast")


func test_each_weapon_slot_keeps_its_own_cooldown() -> void:
	_player.open_perfect_dodge_window()
	_press_heavy()
	assert_false(_weapons.skill_ready())
	_weapons.swap()
	assert_true(_weapons.skill_ready(), "the other weapon keeps its own skill untouched")
	assert_gt(_weapons.skill_cooldown_left(0), 0.0)


func test_a_weapon_without_a_skill_just_charges() -> void:
	var bare: WeaponData = (load("res://data/weapons/pickaxe.tres") as WeaponData).duplicate() as WeaponData
	bare.skill = null
	_weapons.equip(0, bare)
	_player.open_perfect_dodge_window()
	_press_heavy()
	assert_eq(_state(), &"HeavyCharge")
	assert_true(_player.is_perfect_dodge_window(), "nothing consumed")


# --- timing of the press ---------------------------------------------------------------------

func test_the_skill_can_start_out_of_the_dodge_roll() -> void:
	_controller.apply(AttackController.Kind.DODGE, Vector2.RIGHT, 0.0)
	assert_eq(_state(), &"Dodge")
	_player.open_perfect_dodge_window()
	_press_heavy()
	assert_eq(_state(), &"Attack", "no waiting for the roll to end")
	assert_false(_player.is_perfect_dodge_window())


func test_a_skill_press_during_an_attack_is_buffered_until_the_cancel_window() -> void:
	var spec := AttackSpec.new()
	spec.windup_seconds = 0.05
	spec.active_seconds = 0.1
	spec.recovery_seconds = 1.0
	_player.pending_attack = {"spec": spec, "dir": Vector2.RIGHT, "charge": 0.0, "heavy": false}
	_player.state_machine.change_to(&"Attack")
	_tick(0.4)
	_player.open_perfect_dodge_window()
	_press_heavy()
	assert_eq(_controller.buffered_kind(), AttackController.Kind.SKILL, "kept as a skill, not a charge")
	_tick(0.2)
	assert_eq(_player.pending_attack["spec"], _weapons.active_weapon().skill, "fired at the first legal frame")
	assert_false(_player.is_perfect_dodge_window())


func test_releasing_the_button_after_a_skill_does_not_fire_a_heavy() -> void:
	_player.open_perfect_dodge_window()
	_press_heavy()
	_tick(1.0)
	assert_eq(_state(), &"Idle")
	_controller.apply(AttackController.Kind.HEAVY, Vector2.RIGHT, 0.0)
	assert_eq(_state(), &"Idle", "the release that follows a skill press is ignored")


func test_the_skill_hit_is_tagged_and_heavy() -> void:
	var skill: AttackSpec = _weapons.active_weapon().skill
	var hit: HitInfo = _weapons.build_hit(skill, Vector2.RIGHT, 0.0, true)
	assert_true(hit.is_heavy)
	assert_true(hit.tags.has(&"weapon_skill"))
	assert_eq(hit.poise_damage, skill.poise_damage)
	assert_false(_weapons.build_hit(_weapons.take_heavy(), Vector2.RIGHT, 0.0, true).tags.has(&"weapon_skill"))


# --- perfect dodge feedback and the event ------------------------------------------------------------

func test_a_blocked_hit_opens_the_window_and_emits_one_perfect_dodge() -> void:
	_controller.apply(AttackController.Kind.DODGE, Vector2.RIGHT, 0.0)
	_player.hurtbox.emit_signal("blocked_during_dodge", HitInfo.new())
	assert_true(_player.is_perfect_dodge_window())
	assert_eq(_dodges, [true] as Array[bool], "player_dodged(perfect = true) at the block")
	_player.hurtbox.emit_signal("blocked_during_dodge", HitInfo.new())
	_tick(0.4)
	assert_eq(_dodges, [true] as Array[bool], "a second block and the roll ending add nothing")


func test_a_plain_dodge_emits_player_dodged_not_perfect() -> void:
	_controller.apply(AttackController.Kind.DODGE, Vector2.RIGHT, 0.0)
	_tick(0.4)
	assert_eq(_dodges, [false] as Array[bool])


func test_the_owning_client_is_told_when_the_window_opens() -> void:
	var rpc: Dictionary = (_player.get_script() as Script).get_rpc_config() as Dictionary
	assert_true(rpc.has(&"_perfect_window_opened"))
	assert_eq(rpc[&"_perfect_window_opened"]["rpc_mode"], MultiplayerAPI.RPC_MODE_AUTHORITY)
	assert_eq(rpc[&"_perfect_window_opened"]["transfer_mode"], MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	_player._perfect_window_opened()
	assert_true(_player.is_perfect_dodge_window(), "the owner predicts the skill from it")


func test_a_perfect_dodge_freezes_the_dodger_three_frames_and_pings_it() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	var fx := Node2D.new()
	world.add_child(fx)
	var feedback := CombatFeedback.new()
	feedback.name = "CombatFeedback"
	world.add_child(feedback)
	feedback.setup(fx, null)
	var dodger: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	world.add_child(dodger)
	feedback.play_perfect_dodge(dodger)
	var list: Array = TimeManager._entity_effects.get(dodger.get_instance_id(), []) as Array
	assert_eq(list.size(), 1, "frozen")
	assert_eq(int(list[0]["expires_on_frame"]) - Engine.get_physics_frames(), 3, "for three frames")
	var pings: Array[DodgePing] = []
	for child: Node in fx.get_children():
		if child is DodgePing:
			pings.append(child)
	assert_eq(pings.size(), 1, "and a ping ring shows over the dodger")
	assert_lt(pings[0].radius(), DodgePing.END_RADIUS_PX)


# --- a skill shape wider than 180 degrees ----------------------------------------------------------------

func test_the_pickaxe_skill_builds_a_valid_hitbox_and_matching_slash() -> void:
	var skill: AttackSpec = (load("res://data/weapons/pickaxe.tres") as WeaponData).skill
	assert_gt(skill.arc_degrees, 180.0, "setup: wider than a half circle")
	_weapons.begin_swing(skill, Vector2.RIGHT, 0.0, true)
	var shape: ConvexPolygonShape2D = _weapons._hitbox_shape.shape as ConvexPolygonShape2D
	assert_not_null(shape, "a convex hull, not a rejected concave fan")
	var farthest: float = 0.0
	for point: Vector2 in shape.points:
		farthest = maxf(farthest, point.length())
	assert_almost_eq(farthest, skill.reach, 0.01, "reaches the skill's reach")
	var arc: SlashArc = _weapons._slash_arc
	assert_true(arc.is_playing())
	for point: Vector2 in arc.outline():
		assert_lte(point.length(), skill.reach + 0.01, "the wedge stays inside the reach")
	assert_gte(arc.outline().size(), 4, "and is drawable")
