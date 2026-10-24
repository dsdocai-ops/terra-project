extends GutTest
## Tests for `Hurtbox` and `Hitbox` (SPEC-combat-core, "Components"): damage via
## Damage.compute, events, from-behind, invulnerability and the dodge report,
## statuses, knockback hand-off, team filtering and hit-once-per-target.

class Mover:
	extends Node2D
	var facing: Vector2 = Vector2.RIGHT
	var knocked: Array = []

	func apply_knockback(impulse: Vector2, stun: float) -> void:
		knocked.append([impulse, stun])


var _target: Mover
var _hurtbox: Hurtbox
var _health: Health
var _statuses: StatusEffects
var _attacker: Node2D


func before_each() -> void:
	_target = _make_entity(Team.Kind.ENEMY)
	_hurtbox = _target.get_node("Hurtbox")
	_health = _target.get_node("Health")
	_statuses = _target.get_node("StatusEffects")
	_attacker = Node2D.new()
	add_child_autofree(_attacker)
	_attacker.position = Vector2(100, 0)


func _make_entity(team: Team.Kind) -> Mover:
	var entity := Mover.new()
	var stats := StatBlock.new()
	stats.name = "StatBlock"
	stats.base = {StatBlock.Stat.MAX_HP: 100.0, StatBlock.Stat.DEFENSE: 0.0, StatBlock.Stat.ATTACK: 100.0}
	entity.add_child(stats)
	var statuses := StatusEffects.new()
	statuses.name = "StatusEffects"
	entity.add_child(statuses)
	var health := Health.new()
	health.name = "Health"
	entity.add_child(health)
	var hurtbox := Hurtbox.new()
	hurtbox.name = "Hurtbox"
	hurtbox.team = team
	entity.add_child(hurtbox)
	add_child_autofree(entity)
	return entity


func _hit(damage: float = 10.0) -> HitInfo:
	var hit := HitInfo.new()
	hit.base_damage = damage
	hit.source = _attacker
	return hit


func test_receive_computes_damage_and_applies_it() -> void:
	assert_true(_hurtbox.receive(_hit(10.0)))
	assert_eq(_health.current_hp, 90)


func test_receive_uses_the_attackers_attack_stat() -> void:
	var stats := StatBlock.new()
	stats.name = "StatBlock"
	stats.base = {StatBlock.Stat.ATTACK: 200.0}
	_attacker.add_child(stats)
	_hurtbox.receive(_hit(10.0))
	assert_eq(_health.current_hp, 80)


func test_receive_announces_hit_landed_with_target_and_final_damage() -> void:
	var seen: Array[HitInfo] = []
	var listener := func(hit: HitInfo) -> void: seen.append(hit)
	Events.hit_landed.connect(listener)
	_hurtbox.receive(_hit(10.0))
	Events.hit_landed.disconnect(listener)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0].target, _target)
	assert_eq(seen[0].final_damage, 10)


func test_crit_also_emits_crit_landed() -> void:
	watch_signals(Events)
	var hit := _hit(10.0)
	hit.force_crit = true
	_hurtbox.receive(hit)
	assert_signal_emitted(Events, "crit_landed")


func test_invulnerable_target_takes_nothing_and_is_silent() -> void:
	_hurtbox.invulnerable = true
	watch_signals(Events)
	watch_signals(_hurtbox)
	assert_false(_hurtbox.receive(_hit()))
	assert_eq(_health.current_hp, 100)
	assert_signal_not_emitted(Events, "hit_landed")
	assert_signal_not_emitted(_hurtbox, "blocked_during_dodge")


func test_hit_on_a_dodging_target_reports_blocked() -> void:
	_hurtbox.invulnerable = true
	_hurtbox.dodge_invulnerable = true
	watch_signals(_hurtbox)
	assert_false(_hurtbox.receive(_hit()))
	assert_signal_emitted(_hurtbox, "blocked_during_dodge")
	assert_eq(_health.current_hp, 100)


func test_from_behind_is_set_from_facing_and_attacker_position() -> void:
	_target.facing = Vector2.LEFT
	var behind := _hit()
	_hurtbox.receive(behind)
	assert_true(behind.from_behind, "attacker at +x, target faces -x: from behind")
	_target.facing = Vector2.RIGHT
	var front := _hit()
	_hurtbox.receive(front)
	assert_false(front.from_behind, "attacker at +x, target faces +x: from the front")


func test_statuses_are_applied_to_a_survivor() -> void:
	var hit := _hit()
	hit.statuses = [StatusApplication.make(StatusEffects.Status.BURN, 2)]
	_hurtbox.receive(hit)
	assert_true(_statuses.has(StatusEffects.Status.BURN))


func test_knockback_and_stun_are_handed_to_the_entity() -> void:
	var hit := _hit()
	hit.knockback = Vector2(40, 0)
	hit.hit_stun_seconds = 0.3
	_hurtbox.receive(hit)
	assert_eq(_target.knocked.size(), 1)
	assert_eq(_target.knocked[0][0], Vector2(40, 0))
	assert_eq(_target.knocked[0][1], 0.3)


func test_lethal_hit_skips_reactions_but_still_announces() -> void:
	var hit := _hit(500.0)
	hit.knockback = Vector2(40, 0)
	hit.statuses = [StatusApplication.make(StatusEffects.Status.BURN)]
	watch_signals(Events)
	_hurtbox.receive(hit)
	assert_true(_health.is_dead)
	assert_signal_emitted(Events, "hit_landed")
	assert_true(_target.knocked.is_empty())
	assert_false(_statuses.has(StatusEffects.Status.BURN))


func test_dead_target_does_not_receive() -> void:
	var killing := HitInfo.new()
	killing.final_damage = 1000
	_health.apply_damage(killing)
	assert_false(_hurtbox.receive(_hit()))


func test_player_scene_carries_the_real_components() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	add_child_autofree(player)
	assert_true(player.get_node("Health") is Health)
	var hurtbox := player.get_node("Hurtbox") as Hurtbox
	assert_not_null(hurtbox)
	assert_eq(hurtbox.team, Team.Kind.PLAYER)
	assert_eq(hurtbox.collision_layer, Hitbox.LAYER_PLAYER_BODY)


func test_player_hit_emits_player_damaged() -> void:
	var player := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	add_child_autofree(player)
	var stats: StatBlock = player.get_node("StatBlock")
	stats.set_base(StatBlock.Stat.MAX_HP, 100.0)
	var health: Health = player.get_node("Health")
	health.refill()
	watch_signals(Events)
	assert_true((player.get_node("Hurtbox") as Hurtbox).receive(_hit(10.0)))
	assert_signal_emitted(Events, "player_damaged")
	var params: Array = get_signal_parameters(Events, "player_damaged")
	assert_eq(params[0], player)
	assert_true(params[1] is HitInfo, "player_damaged carries the HitInfo (SPEC-effect-system)")
	assert_eq(health.current_hp, 90)


func test_source_and_target_without_stat_blocks_still_resolve() -> void:
	var bare := Node2D.new()
	var health := Health.new()
	health.name = "Health"
	var hurtbox := Hurtbox.new()
	hurtbox.name = "Hurtbox"
	bare.add_child(health)
	bare.add_child(hurtbox)
	add_child_autofree(bare)
	var hit := HitInfo.new()
	hit.base_damage = 1.0
	assert_true(hurtbox.receive(hit))
	assert_eq(hit.final_damage, 1)


func test_hurtbox_layer_follows_team() -> void:
	assert_eq(_hurtbox.collision_layer, Hitbox.LAYER_ENEMY_BODY)
	_hurtbox.team = Team.Kind.PLAYER
	assert_eq(_hurtbox.collision_layer, Hitbox.LAYER_PLAYER_BODY)


# Hitbox ---------------------------------------------------------------------

func _hitbox(team: Team.Kind = Team.Kind.PLAYER) -> Hitbox:
	var hitbox := Hitbox.new()
	hitbox.team = team
	hitbox.template = _hit(10.0)
	add_child_autofree(hitbox)
	return hitbox


func test_inactive_hitbox_hits_nothing() -> void:
	var hitbox := _hitbox()
	assert_false(hitbox.try_hit(_hurtbox))
	assert_eq(_health.current_hp, 100)


func test_active_hitbox_hits_an_opposing_hurtbox() -> void:
	var hitbox := _hitbox()
	hitbox.active = true
	watch_signals(hitbox)
	assert_true(hitbox.try_hit(_hurtbox))
	assert_eq(_health.current_hp, 90)
	assert_signal_emitted(hitbox, "hit_connected")


func test_hitbox_ignores_its_own_team() -> void:
	var hitbox := _hitbox(Team.Kind.ENEMY)
	hitbox.active = true
	assert_false(hitbox.try_hit(_hurtbox), "an enemy hitbox does not hurt an enemy")
	assert_eq(_health.current_hp, 100)


func test_hit_once_per_target_until_reactivated() -> void:
	var hitbox := _hitbox()
	hitbox.active = true
	assert_true(hitbox.try_hit(_hurtbox))
	assert_false(hitbox.try_hit(_hurtbox))
	hitbox.active = false
	hitbox.active = true
	assert_true(hitbox.try_hit(_hurtbox), "a new activation starts a fresh target set")
	assert_eq(_health.current_hp, 80)


func test_repeat_hits_allowed_when_not_once_per_target() -> void:
	var hitbox := _hitbox()
	hitbox.hit_once_per_target = false
	hitbox.active = true
	hitbox.try_hit(_hurtbox)
	hitbox.try_hit(_hurtbox)
	assert_eq(_health.current_hp, 80)


func test_template_is_copied_per_target() -> void:
	var hitbox := _hitbox()
	hitbox.active = true
	hitbox.try_hit(_hurtbox)
	assert_eq(hitbox.template.final_damage, 0, "the template is never filled in")


func test_layers_follow_team() -> void:
	var player_box := _hitbox(Team.Kind.PLAYER)
	assert_eq(player_box.collision_layer, Hitbox.LAYER_HITBOX_PLAYER)
	assert_eq(player_box.collision_mask, Hitbox.LAYER_ENEMY_BODY)
	var enemy_box := _hitbox(Team.Kind.ENEMY)
	assert_eq(enemy_box.collision_layer, Hitbox.LAYER_HITBOX_ENEMY)
	assert_eq(enemy_box.collision_mask, Hitbox.LAYER_PLAYER_BODY)


func test_overlap_through_physics_hits_once() -> void:
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	_hurtbox.add_child(shape)
	var hitbox := _hitbox()
	var box_shape := CollisionShape2D.new()
	box_shape.shape = CircleShape2D.new()
	hitbox.add_child(box_shape)
	hitbox.global_position = _target.global_position
	hitbox.active = true
	await wait_physics_frames(4)
	assert_eq(_health.current_hp, 90, "area_entered delivered exactly one hit")
