extends GutTest
## Tests for hit feedback (SPEC-combat-core "Hit feedback", combat v2 C1):
## hit-stop tiers, entities that actually freeze, the replicated feedback
## payload, the hit flash, camera shake, the slash arc and the finisher tag.
## Owned by combat-core. TimeManager is global, so the hit-stop source is
## cleared after every test.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"
const FRAME := 1.0 / 60.0

var _world: Node2D
var _fx: Node2D
var _feedback: CombatFeedback


func before_each() -> void:
	_world = Node2D.new()
	_world.name = "FakeWorld"
	add_child_autofree(_world)
	_fx = Node2D.new()
	_fx.name = "FX"
	_world.add_child(_fx)
	_feedback = CombatFeedback.new()
	_feedback.name = "CombatFeedback"
	_world.add_child(_feedback)
	_feedback.setup(_fx, null)


func after_each() -> void:
	TimeManager.clear_source(TimeManager.HIT_STOP_SOURCE)


func _player() -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_world.add_child(player)
	player.position = Vector2.ZERO
	return player


func _enemy(kind: StringName = &"rock_tick") -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	enemy.setup(kind)
	_world.add_child(enemy)
	return enemy


## Physics frames of hit-stop left on `node` (0 when none).
func _stop_frames(node: Node) -> int:
	var list: Array = TimeManager._entity_effects.get(node.get_instance_id(), []) as Array
	for effect: Dictionary in list:
		if effect["source"] == TimeManager.HIT_STOP_SOURCE:
			return int(effect["expires_on_frame"]) - Engine.get_physics_frames()
	return 0


func _hit(source: Node, target: Node, heavy: bool = false, crit: bool = false, damage: int = 12) -> HitInfo:
	var hit := HitInfo.new()
	hit.source = source
	hit.target = target
	hit.is_heavy = heavy
	hit.is_crit = crit
	hit.final_damage = damage
	return hit


# --- tier table -----------------------------------------------------------------

func test_hit_stop_tiers_match_the_table() -> void:
	assert_eq(CombatFeedbackConstants.hit_stop_frames(false, false, false, false), 3, "light")
	assert_eq(CombatFeedbackConstants.hit_stop_frames(true, false, false, false), 6, "finisher or heavy")
	assert_eq(CombatFeedbackConstants.hit_stop_frames(false, true, false, false), 5, "light crit adds 2")
	assert_eq(CombatFeedbackConstants.hit_stop_frames(true, true, false, false), 8, "heavy crit adds 2")
	assert_eq(CombatFeedbackConstants.hit_stop_frames(false, false, true, false), 4, "player hurt")
	assert_eq(CombatFeedbackConstants.hit_stop_frames(true, true, false, true), 10, "boss kill overrides")


func test_shake_tiers_match_the_table() -> void:
	assert_eq(CombatFeedbackConstants.shake_px(false, false, false, false), 0.0, "light: none")
	assert_eq(CombatFeedbackConstants.shake_px(true, false, false, false), 2.0, "heavy")
	assert_eq(CombatFeedbackConstants.shake_px(true, true, false, false), 3.0, "crit adds 1")
	assert_eq(CombatFeedbackConstants.shake_px(false, false, true, false), 3.0, "player hurt")
	assert_eq(CombatFeedbackConstants.shake_px(false, false, false, true), 8.0, "boss kill")


# --- hit-stop is called on a landed hit ------------------------------------------

func test_a_light_hit_freezes_attacker_and_target_for_three_frames() -> void:
	var player: Player = _player()
	var enemy: Enemy = _enemy()
	Events.hit_landed.emit(_hit(player, enemy))
	assert_eq(_stop_frames(enemy), 3)
	assert_eq(_stop_frames(player), 3, "the attacker freezes with the target")


func test_a_heavy_hit_freezes_six_frames_and_a_crit_adds_two() -> void:
	var player: Player = _player()
	var enemy: Enemy = _enemy()
	Events.hit_landed.emit(_hit(player, enemy, true))
	assert_eq(_stop_frames(enemy), 6)
	Events.hit_landed.emit(_hit(player, enemy, true, true))
	assert_eq(_stop_frames(enemy), 8)


func test_a_light_combo_finisher_uses_the_heavy_tier() -> void:
	var player: Player = _player()
	var enemy: Enemy = _enemy()
	var hit: HitInfo = _hit(player, enemy)
	hit.tags.append(CombatFeedback.FINISHER_TAG)
	Events.hit_landed.emit(hit)
	assert_eq(_stop_frames(enemy), 6)


func test_a_player_hurt_freezes_the_player_only_for_four_frames() -> void:
	var player: Player = _player()
	var enemy: Enemy = _enemy()
	Events.hit_landed.emit(_hit(enemy, player))
	assert_eq(_stop_frames(player), 4)
	assert_eq(_stop_frames(enemy), 0, "the enemy that hit keeps moving")


func test_a_projectile_hit_does_not_freeze_the_shooter() -> void:
	var player: Player = _player()
	var enemy: Enemy = _enemy()
	var hit: HitInfo = _hit(player, enemy)
	hit.is_projectile = true
	Events.hit_landed.emit(hit)
	assert_eq(_stop_frames(enemy), 3)
	assert_eq(_stop_frames(player), 0)


func test_a_boss_kill_freezes_ten_frames() -> void:
	var player: Player = _player()
	var enemy: Enemy = _enemy()
	enemy.add_to_group(CombatFeedback.BOSS_GROUP)
	enemy.health.apply_damage(_hit(player, enemy, false, false, 99999))
	assert_true(enemy.health.is_dead, "setup: the boss died")
	Events.hit_landed.emit(_hit(player, enemy))
	assert_eq(_stop_frames(enemy), 10)


# --- frozen entities do not move ----------------------------------------------------

func test_a_player_with_scale_zero_does_not_walk() -> void:
	var player: Player = _player()
	player.move_input = Vector2(1, 0)
	TimeManager.hit_stop(player, player, 3)
	for _frame in 3:
		player.state_machine.physics_update(FRAME)
	assert_eq(player.position, Vector2.ZERO, "frozen for the whole hit-stop")
	TimeManager.clear_source(TimeManager.HIT_STOP_SOURCE)
	player.state_machine.physics_update(FRAME)
	assert_gt(player.position.length(), 0.0, "walks again once it ends")


func test_a_player_with_scale_zero_does_not_dodge_or_slide() -> void:
	var player: Player = _player()
	player.pending_dodge_dir = Vector2.RIGHT
	player.state_machine.change_to(&"Dodge")
	TimeManager.hit_stop(player, player, 4)
	for _frame in 4:
		player.state_machine.physics_update(FRAME)
	assert_eq(player.position, Vector2.ZERO, "a dodge roll holds still too")
	player.state_machine.change_to(&"Idle")
	player.apply_knockback(Vector2(200, 0), 0.5)
	for _frame in 4:
		player.state_machine.physics_update(FRAME)
	assert_eq(player.position, Vector2.ZERO, "so does a knockback slide")


func test_an_attack_with_scale_zero_does_not_advance() -> void:
	var player: Player = _player()
	var spec := AttackSpec.new()
	spec.windup_seconds = 0.05
	player.pending_attack = {"spec": spec, "dir": Vector2.RIGHT, "charge": 0.0, "heavy": false}
	player.state_machine.change_to(&"Attack")
	TimeManager.hit_stop(player, player, 6)
	for _frame in 6:
		player.state_machine.physics_update(FRAME)
	assert_eq(player.state_machine.current_name(), &"Attack")
	assert_false((player.get_node("WeaponController") as WeaponController)._hitbox.active, "the swing has not gone live")


func test_an_enemy_with_scale_zero_does_not_slide_from_knockback() -> void:
	var enemy: Enemy = _enemy()
	enemy.apply_knockback(Vector2(300, 0), 0.5)
	assert_eq(enemy.machine.current_name(), &"HitStun")
	TimeManager.hit_stop(enemy, enemy, 5)
	for _frame in 5:
		enemy.machine.physics_update(FRAME)
	assert_eq(enemy.position, Vector2.ZERO)
	TimeManager.clear_source(TimeManager.HIT_STOP_SOURCE)
	enemy.machine.physics_update(FRAME)
	assert_gt(enemy.position.x, 0.0, "slides once it ends")


func test_a_partial_slow_slows_a_dodge_roll() -> void:
	var fast: Player = _player()
	fast.pending_dodge_dir = Vector2.RIGHT
	fast.state_machine.change_to(&"Dodge")
	fast.state_machine.physics_update(FRAME)
	var slow: Player = _player()
	slow.position = Vector2(0, 200)
	slow.pending_dodge_dir = Vector2.RIGHT
	slow.state_machine.change_to(&"Dodge")
	TimeManager.set_entity_scale(slow, 0.5, 1.0, &"test_slow")
	slow.state_machine.physics_update(FRAME)
	TimeManager.clear_source(&"test_slow")
	assert_lt(slow.position.x, fast.position.x * 0.75, "half-speed time covers about half the distance")


# --- replicated feedback ---------------------------------------------------------------

func test_the_payload_names_the_target_relative_to_the_world() -> void:
	var enemy: Enemy = _enemy()
	var payload: Dictionary = _feedback.make_payload(_hit(null, enemy, true, true, 31), enemy)
	assert_eq(_world.get_node_or_null(payload["target_path"]), enemy)
	assert_eq(payload["final_damage"], 31)
	assert_true(payload["is_crit"])
	assert_true(payload["is_heavy"])
	assert_false(payload["staggered"])


func test_a_client_receiving_the_rpc_spawns_a_damage_number() -> void:
	var enemy: Enemy = _enemy()
	enemy.position = Vector2(50, 20)
	var payload: Dictionary = _feedback.make_payload(_hit(null, enemy, false, false, 17), enemy)
	# The RPC entry point a client runs when the host's packet arrives.
	_feedback._receive_feedback(payload)
	var numbers: Array[DamageNumber] = []
	for child: Node in _fx.get_children():
		if child is DamageNumber:
			numbers.append(child)
	assert_eq(numbers.size(), 1, "one number")
	assert_eq(numbers[0].text, "17")


func test_feedback_spawns_a_spark_sized_by_the_hit() -> void:
	var enemy: Enemy = _enemy()
	_feedback.play_feedback(_feedback.make_payload(_hit(null, enemy), enemy))
	_feedback.play_feedback(_feedback.make_payload(_hit(null, enemy, true), enemy))
	var sparks: Array[HitSpark] = []
	for child: Node in _fx.get_children():
		if child is HitSpark:
			sparks.append(child)
	assert_eq(sparks.size(), 2)
	assert_false(sparks[0].large, "light: small")
	assert_true(sparks[1].large, "heavy: large")


func test_the_rpc_is_unreliable_and_called_locally() -> void:
	var config: Dictionary = {}
	for entry: Dictionary in _feedback.get_method_list():
		if entry["name"] == &"_receive_feedback":
			config = entry
	assert_false(config.is_empty(), "the RPC method exists")
	var rpc: Dictionary = (_feedback.get_script() as Script).get_rpc_config() as Dictionary
	assert_true(rpc.has(&"_receive_feedback"), "registered as an rpc")
	assert_eq(rpc[&"_receive_feedback"]["transfer_mode"], MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	assert_true(rpc[&"_receive_feedback"]["call_local"], "the host plays it too")


func test_a_missing_target_is_ignored() -> void:
	_feedback.play_feedback({"target_path": NodePath("Nope"), "final_damage": 5})
	assert_eq(_fx.get_child_count(), 0)


# --- flash -----------------------------------------------------------------------------------

func test_the_flash_runs_four_frames_then_resets() -> void:
	var sprite := Sprite2D.new()
	add_child_autofree(sprite)
	var flash: HitFlash = HitFlash.attach(sprite, [sprite])
	var material: ShaderMaterial = sprite.material as ShaderMaterial
	assert_not_null(material, "the shader material is on the sprite")
	assert_eq(float(material.get_shader_parameter(&"flash_amount")), 0.0, "starts clear")
	flash.flash(HitFlash.WHITE, 4)
	assert_true(flash.is_flashing())
	assert_eq(float(material.get_shader_parameter(&"flash_amount")), 1.0, "full on the first frame")
	var last: float = 1.0
	for _frame in 3:
		flash.step()
		var now: float = float(material.get_shader_parameter(&"flash_amount"))
		assert_lt(now, last, "fades each frame")
		last = now
	flash.step()
	assert_false(flash.is_flashing(), "over after four frames")
	assert_eq(float(material.get_shader_parameter(&"flash_amount")), 0.0, "reset to clear")


func test_a_new_hit_restarts_the_flash() -> void:
	var sprite := Sprite2D.new()
	add_child_autofree(sprite)
	var flash: HitFlash = HitFlash.attach(sprite, [sprite])
	flash.flash(HitFlash.WHITE, 4)
	flash.step()
	flash.step()
	flash.flash(HitFlash.GOLD, 4)
	assert_eq(flash.amount(), 1.0)
	var material: ShaderMaterial = sprite.material as ShaderMaterial
	assert_eq(material.get_shader_parameter(&"flash_color"), HitFlash.GOLD)


func test_enemies_and_players_carry_a_flash_on_their_sprites() -> void:
	var enemy: Enemy = _enemy()
	var player: Player = _player()
	assert_not_null(enemy.get_node_or_null("HitFlash"))
	assert_true(enemy.sprite.material is ShaderMaterial)
	assert_true(enemy.body.material is ShaderMaterial)
	assert_not_null(player.get_node_or_null("HitFlash"))
	assert_true(player.sprite.material is ShaderMaterial)


func test_feedback_flashes_gold_on_a_crit_and_red_on_a_player() -> void:
	var enemy: Enemy = _enemy()
	var player: Player = _player()
	_feedback.play_feedback(_feedback.make_payload(_hit(null, enemy, false, true), enemy))
	assert_eq(enemy.body.material.get_shader_parameter(&"flash_color"), HitFlash.GOLD)
	_feedback.play_feedback(_feedback.make_payload(_hit(null, enemy), enemy))
	assert_eq(enemy.body.material.get_shader_parameter(&"flash_color"), HitFlash.WHITE)
	_feedback.play_feedback(_feedback.make_payload(_hit(null, player), player))
	assert_eq(player.sprite.material.get_shader_parameter(&"flash_color"), HitFlash.RED)


# --- shake -----------------------------------------------------------------------------------

func test_shake_follows_the_tiers() -> void:
	var camera := GameCamera.new()
	add_child_autofree(camera)
	_feedback.setup(_fx, camera)
	var enemy: Enemy = _enemy()
	_feedback.play_feedback(_feedback.make_payload(_hit(null, enemy), enemy))
	assert_eq(camera.trauma, 0.0, "a light hit does not shake")
	_feedback.play_feedback(_feedback.make_payload(_hit(null, enemy, true), enemy))
	assert_almost_eq(camera.trauma, 2.0 / GameCamera.MAX_SHAKE_PX, 0.001, "heavy shakes 2")
	camera.trauma = 0.0
	_feedback.play_feedback(_feedback.make_payload(_hit(null, enemy, true, true), enemy))
	assert_almost_eq(camera.trauma, 3.0 / GameCamera.MAX_SHAKE_PX, 0.001, "a crit adds 1")


func test_player_hurt_shakes_only_the_local_players_camera() -> void:
	var camera := GameCamera.new()
	add_child_autofree(camera)
	_feedback.setup(_fx, camera)
	var player: Player = _player()
	player.peer_id = multiplayer.get_unique_id()
	_feedback.play_feedback(_feedback.make_payload(_hit(null, player), player))
	assert_almost_eq(camera.trauma, 3.0 / GameCamera.MAX_SHAKE_PX, 0.001, "local player: 3")
	camera.trauma = 0.0
	player.peer_id = multiplayer.get_unique_id() + 7
	_feedback.play_feedback(_feedback.make_payload(_hit(null, player), player))
	assert_eq(camera.trauma, 0.0, "another player's hurt does not shake this peer")


# --- slash arc -------------------------------------------------------------------------------

func test_the_slash_arc_matches_the_attack_shape() -> void:
	var arc := SlashArc.new()
	add_child_autofree(arc)
	arc.play(AttackSpec.Shape.ARC, 56.0, 110.0, Vector2.RIGHT, 0.12, Color.WHITE)
	assert_true(arc.is_playing())
	var points: PackedVector2Array = arc.outline()
	assert_eq(points[0], Vector2.ZERO, "wedge apex at the player")
	for index in range(1, points.size()):
		assert_almost_eq(points[index].length(), 56.0, 0.01, "every rim point sits at the reach")
	assert_almost_eq(rad_to_deg(points[1].angle_to(points[points.size() - 1])), 110.0, 0.5, "spans the arc")
	arc.play(AttackSpec.Shape.CIRCLE, 78.0, 0.0, Vector2.RIGHT, 0.16, Color.WHITE)
	for point: Vector2 in arc.outline():
		assert_almost_eq(point.length(), 78.0, 0.01, "a circle at the reach")


func test_the_slash_arc_plays_for_the_active_window_then_clears() -> void:
	var arc := SlashArc.new()
	add_child_autofree(arc)
	arc.play(AttackSpec.Shape.ARC, 56.0, 110.0, Vector2.RIGHT, 0.12, Color.WHITE)
	arc.step(0.1)
	assert_true(arc.is_playing())
	arc.step(0.03)
	assert_false(arc.is_playing())
	assert_false(arc.visible)


func test_a_projectile_attack_draws_no_slash() -> void:
	var arc := SlashArc.new()
	add_child_autofree(arc)
	arc.play(AttackSpec.Shape.PROJECTILE, 300.0, 0.0, Vector2.RIGHT, 0.1, Color.WHITE)
	assert_false(arc.is_playing())


func test_the_swing_plays_the_slash_with_the_charged_reach() -> void:
	var player: Player = _player()
	var weapons: WeaponController = player.get_node("WeaponController") as WeaponController
	var spec: AttackSpec = weapons.take_heavy()
	weapons.begin_swing(spec, Vector2.RIGHT, 1.0, true)
	var arc: SlashArc = weapons._slash_arc
	assert_true(arc.is_playing(), "begin_swing shows the swing")
	assert_almost_eq(arc.reach, WeaponController.melee_reach(spec, 1.0, true), 0.001)
	assert_gt(arc.reach, spec.reach, "a full charge reaches further")
	weapons.end_swing()
	assert_false(arc.is_playing(), "end_swing clears it")


func test_a_remote_peer_plays_the_hosts_swing_rpc() -> void:
	var player: Player = _player()
	var weapons: WeaponController = player.get_node("WeaponController") as WeaponController
	var rpc: Dictionary = (weapons.get_script() as Script).get_rpc_config() as Dictionary
	assert_true(rpc.has(&"_remote_swing"), "the swing RPC is registered")
	assert_eq(rpc[&"_remote_swing"]["transfer_mode"], MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	assert_false(rpc[&"_remote_swing"]["call_local"], "the host already played its own copy")


# --- finisher tag -------------------------------------------------------------------------------

func test_only_the_last_light_step_is_tagged_a_finisher() -> void:
	var player: Player = _player()
	var weapons: WeaponController = player.get_node("WeaponController") as WeaponController
	var combo: Array[AttackSpec] = weapons.active_weapon().light_combo
	assert_false(weapons.build_hit(combo[0], Vector2.RIGHT, 0.0, false).tags.has(CombatFeedback.FINISHER_TAG))
	assert_true(weapons.build_hit(combo[combo.size() - 1], Vector2.RIGHT, 0.0, false).tags.has(CombatFeedback.FINISHER_TAG))
	assert_false(weapons.build_hit(weapons.take_heavy(), Vector2.RIGHT, 0.0, true).tags.has(CombatFeedback.FINISHER_TAG), "a heavy is not a finisher, it is already heavy")
