extends GutTest
## Tests for poise and stagger (combat v2 C2, SPEC-combat-core "Hit reactions"):
## a flinch keeps a windup going, a poise break cancels it and emits
## `enemy_staggered`, poise refills on schedule, a staggered enemy takes x1.25,
## and a 0-poise enemy staggers on every hit. Owned by combat-core. Steps the
## enemy by hand so the physics server never runs between asserts. TimeManager
## is global, so its sources are cleared after every test.

const ENEMY_SCENE := "res://scenes/enemies/enemy.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FRAME := 1.0 / 60.0

var _world: Node2D
var _staggered_events: Array[HitInfo] = []


func before_each() -> void:
	_world = Node2D.new()
	add_child_autofree(_world)
	_staggered_events.clear()
	Events.enemy_staggered.connect(_on_enemy_staggered)


func after_each() -> void:
	if Events.enemy_staggered.is_connected(_on_enemy_staggered):
		Events.enemy_staggered.disconnect(_on_enemy_staggered)
	TimeManager.clear_source(TimeManager.HIT_STOP_SOURCE)
	TimeManager.clear_source(&"test")


func _on_enemy_staggered(_enemy: Node, hit: HitInfo) -> void:
	_staggered_events.append(hit)


func _enemy(kind: StringName = &"hollow_miner") -> Enemy:
	var enemy: Enemy = (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	enemy.setup(kind)
	_world.add_child(enemy)
	return enemy


func _hit(poise: float, base: float = 5.0) -> HitInfo:
	var hit := HitInfo.new()
	hit.base_damage = base
	hit.poise_damage = poise
	hit.knockback = Vector2(120, 0)
	hit.hit_stun_seconds = 0.15
	return hit


## Steps the enemy and its state machine `seconds` of game time.
func _step(enemy: Enemy, seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.0:
		var dt: float = minf(FRAME, remaining)
		enemy._physics_process(dt)
		enemy.machine.physics_update(dt)
		remaining -= dt


## Puts the enemy mid-windup on its first attack.
func _winding_up(enemy: Enemy) -> void:
	enemy.next_attack = enemy.data.attacks[0]
	enemy.machine.change_to(&"Attack")
	_step(enemy, 0.2)


# --- data -------------------------------------------------------------------------

func test_the_collapsed_mines_enemies_carry_the_authored_poise() -> void:
	assert_eq(EnemyData.find(&"rock_tick").poise, 0.0, "fodder")
	assert_eq(EnemyData.find(&"hollow_miner").poise, 40.0)
	assert_eq(EnemyData.find(&"lantern_wisp").poise, 20.0)
	assert_eq(EnemyData.find(&"hollow_miner").stagger_seconds, 0.8, "default stagger")


func test_the_weapons_carry_light_finisher_and_heavy_poise_damage() -> void:
	var pickaxe: WeaponData = load("res://data/weapons/pickaxe.tres") as WeaponData
	assert_eq(pickaxe.light_combo[0].poise_damage, 10.0)
	assert_eq(pickaxe.light_combo[1].poise_damage, 10.0)
	assert_eq(pickaxe.light_combo[2].poise_damage, 20.0, "the finisher")
	assert_eq(pickaxe.heavy.poise_damage, 30.0)
	var crossbow: WeaponData = load("res://data/weapons/crossbow.tres") as WeaponData
	assert_eq(crossbow.light_combo[0].poise_damage, 10.0)
	assert_eq(crossbow.heavy.poise_damage, 30.0)


func test_build_hit_fills_poise_damage_and_a_charge_adds_thirty() -> void:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_world.add_child(player)
	var weapons: WeaponController = player.get_node("WeaponController") as WeaponController
	var combo: Array[AttackSpec] = weapons.active_weapon().light_combo
	assert_eq(weapons.build_hit(combo[0], Vector2.RIGHT, 0.0, false).poise_damage, 10.0, "light")
	assert_eq(weapons.build_hit(combo[2], Vector2.RIGHT, 0.0, false).poise_damage, 20.0, "finisher")
	var heavy: AttackSpec = weapons.take_heavy()
	assert_eq(weapons.build_hit(heavy, Vector2.RIGHT, 0.0, true).poise_damage, 30.0, "uncharged heavy")
	assert_eq(weapons.build_hit(heavy, Vector2.RIGHT, 1.0, true).poise_damage, 60.0, "full charge adds 30")
	assert_eq(weapons.build_hit(heavy, Vector2.RIGHT, 0.5, true).poise_damage, 45.0, "half charge adds 15")


func test_hit_info_copies_the_poise_fields() -> void:
	var hit: HitInfo = _hit(25.0)
	hit.staggered = true
	var clone: HitInfo = hit.copy()
	assert_eq(clone.poise_damage, 25.0)
	assert_true(clone.staggered)


# --- flinch -------------------------------------------------------------------------

func test_a_flinch_keeps_the_windup_and_its_telegraph() -> void:
	var enemy: Enemy = _enemy()
	_winding_up(enemy)
	var before: float = enemy.telegraph_progress
	assert_gt(before, 0.0, "setup: the telegraph is filling")
	assert_true(enemy.hurtbox.receive(_hit(10.0)))
	assert_eq(enemy.machine.current_name(), &"Attack", "no state change")
	assert_eq(enemy.poise, 30.0, "poise drained by the hit")
	_step(enemy, 0.1)
	assert_gt(enemy.telegraph_progress, before, "the windup kept winding up")
	assert_false(_staggered_events.size() > 0, "no stagger event")


func test_a_flinch_still_shoves_the_enemy_and_does_not_stun_it() -> void:
	var enemy: Enemy = _enemy()
	_winding_up(enemy)
	var x: float = enemy.position.x
	enemy.hurtbox.receive(_hit(10.0))
	_step(enemy, 0.1)
	assert_gt(enemy.position.x, x, "knocked back along the hit")
	assert_eq(enemy.machine.current_name(), &"Attack")


func test_a_flinch_respects_knockback_resist() -> void:
	var enemy: Enemy = _enemy()
	enemy.data = enemy.data.duplicate() as EnemyData
	enemy.data.knockback_resist = 1.0
	_winding_up(enemy)
	enemy.hurtbox.receive(_hit(10.0))
	assert_eq(enemy.knockback_velocity, Vector2.ZERO, "fully resisted")


# --- break ----------------------------------------------------------------------------

func test_a_break_cancels_the_attack_and_emits_enemy_staggered() -> void:
	var enemy: Enemy = _enemy()
	_winding_up(enemy)
	var hit: HitInfo = _hit(40.0)
	assert_true(enemy.hurtbox.receive(hit))
	assert_eq(enemy.machine.current_name(), &"Stagger")
	assert_eq(enemy.telegraph_progress, -1.0, "telegraph cleared")
	assert_false(enemy.hitbox.active, "nothing can hit")
	assert_true(hit.staggered, "the hit says it staggered")
	assert_true(enemy.staggered, "the replicated flag is up")
	assert_eq(_staggered_events.size(), 1)
	assert_eq(_staggered_events[0], hit, "the event carries the breaking hit")


func test_several_flinches_add_up_to_a_break() -> void:
	var enemy: Enemy = _enemy()
	for _i in 3:
		enemy.hurtbox.receive(_hit(10.0))
	assert_eq(enemy.machine.current_name(), &"Idle", "30 of 40 poise gone, still standing")
	enemy.hurtbox.receive(_hit(10.0))
	assert_eq(enemy.machine.current_name(), &"Stagger")


func test_stagger_resist_scales_the_poise_damage_taken() -> void:
	var enemy: Enemy = _enemy()
	enemy.data = enemy.data.duplicate() as EnemyData
	enemy.data.stagger_resist = 0.5
	enemy.hurtbox.receive(_hit(20.0))
	assert_eq(enemy.poise, 30.0, "half of 20 drained")


func test_stagger_lasts_its_seconds_then_frees_the_enemy_with_full_poise() -> void:
	var enemy: Enemy = _enemy()
	enemy.hurtbox.receive(_hit(40.0))
	assert_eq(enemy.poise, 0.0)
	_step(enemy, 0.7)
	assert_eq(enemy.machine.current_name(), &"Stagger", "still dazed at 0.7 s")
	_step(enemy, 0.15)
	assert_ne(enemy.machine.current_name(), &"Stagger", "free after 0.8 s (Chase, then Idle with nobody to chase)")
	assert_eq(enemy.poise, 40.0, "full poise on the way out")
	assert_false(enemy.staggered)


func test_a_hit_while_staggered_does_not_restart_or_re_emit() -> void:
	var enemy: Enemy = _enemy()
	enemy.hurtbox.receive(_hit(40.0))
	_step(enemy, 0.5)
	var hit: HitInfo = _hit(40.0)
	enemy.hurtbox.receive(hit)
	assert_false(hit.staggered, "already down")
	assert_eq(_staggered_events.size(), 1, "one event for one stagger")
	_step(enemy, 0.35)
	assert_ne(enemy.machine.current_name(), &"Stagger", "the first stagger's clock ran on")


# --- refill ---------------------------------------------------------------------------

func test_poise_waits_one_and_a_half_seconds_then_refills_half_per_second() -> void:
	var enemy: Enemy = _enemy()
	enemy.hurtbox.receive(_hit(20.0))
	assert_eq(enemy.poise, 20.0)
	_step(enemy, 1.4)
	assert_eq(enemy.poise, 20.0, "nothing refilled yet at 1.4 s")
	_step(enemy, 0.6)
	# 0.5 s of refill at 50% of 40 per second = +10.
	assert_almost_eq(enemy.poise, 30.0, 0.5, "refilling after the delay")
	_step(enemy, 1.0)
	assert_eq(enemy.poise, 40.0, "capped at the maximum")


func test_a_new_hit_restarts_the_refill_delay() -> void:
	var enemy: Enemy = _enemy()
	enemy.hurtbox.receive(_hit(10.0))
	_step(enemy, 1.0)
	enemy.hurtbox.receive(_hit(10.0))
	_step(enemy, 1.0)
	assert_eq(enemy.poise, 20.0, "1 s since the last hit, still waiting")


func test_poise_refill_uses_timemanager_scaled_time() -> void:
	var enemy: Enemy = _enemy()
	enemy.hurtbox.receive(_hit(20.0))
	TimeManager.set_entity_scale(enemy, 0.0, 60.0, &"test")
	_step(enemy, 5.0)
	assert_eq(enemy.poise, 20.0, "a time stop holds the refill")
	TimeManager.clear_source(&"test")
	_step(enemy, 2.0)
	assert_gt(enemy.poise, 20.0)


# --- damage while staggered -------------------------------------------------------------

func test_a_staggered_enemy_takes_a_quarter_more_damage() -> void:
	var enemy: Enemy = _enemy()
	var normal: HitInfo = _hit(0.0, 8.0)
	enemy.hurtbox.receive(normal)
	enemy.hurtbox.receive(_hit(40.0, 1.0))
	assert_eq(enemy.machine.current_name(), &"Stagger", "setup")
	var bonus: HitInfo = _hit(0.0, 8.0)
	enemy.hurtbox.receive(bonus)
	assert_eq(bonus.final_damage, roundi(float(normal.final_damage) * 1.25))
	assert_gt(bonus.final_damage, normal.final_damage)


func test_the_damage_bonus_ends_with_the_stagger_and_never_touches_base_stats() -> void:
	var enemy: Enemy = _enemy()
	var defense: float = enemy.stat_block.get_value(StatBlock.Stat.DEFENSE)
	var base: Dictionary = enemy.stat_block.base.duplicate()
	enemy.hurtbox.receive(_hit(40.0))
	assert_eq(enemy.hurtbox.damage_taken_factor(), 1.25)
	_step(enemy, 0.9)
	assert_eq(enemy.hurtbox.damage_taken_factor(), 1.0, "gone when the stagger ends")
	assert_eq(enemy.stat_block.get_value(StatBlock.Stat.DEFENSE), defense)
	assert_eq(enemy.stat_block.base, base, "base stats untouched")


func test_hurtbox_damage_factors_multiply_by_source() -> void:
	var enemy: Enemy = _enemy()
	enemy.hurtbox.set_damage_taken_factor(&"a", 1.25)
	enemy.hurtbox.set_damage_taken_factor(&"b", 2.0)
	assert_almost_eq(enemy.hurtbox.damage_taken_factor(), 2.5, 0.0001)
	enemy.hurtbox.clear_damage_taken_factor(&"a")
	assert_eq(enemy.hurtbox.damage_taken_factor(), 2.0)


# --- fodder ---------------------------------------------------------------------------------

func test_a_zero_poise_enemy_staggers_on_every_hit() -> void:
	var enemy: Enemy = _enemy(&"rock_tick")
	assert_eq(enemy.poise_max, 0.0)
	for round_index in 3:
		var hit: HitInfo = _hit(10.0)
		enemy.hurtbox.receive(hit)
		assert_true(hit.staggered, "hit %d staggered" % round_index)
		assert_eq(enemy.machine.current_name(), &"Stagger")
		_step(enemy, 0.9)
		assert_ne(enemy.machine.current_name(), &"Stagger")
	assert_eq(_staggered_events.size(), 3)


func test_a_hit_with_no_poise_damage_does_not_stagger_fodder() -> void:
	var enemy: Enemy = _enemy(&"rock_tick")
	var hit: HitInfo = _hit(0.0)
	enemy.hurtbox.receive(hit)
	assert_false(hit.staggered)
	assert_ne(enemy.machine.current_name(), &"Stagger")


# --- legacy and sync ----------------------------------------------------------------------------

func test_the_two_argument_knockback_is_still_a_full_stun() -> void:
	var enemy: Enemy = _enemy()
	enemy.apply_knockback(Vector2(60, 0), 0.3)
	assert_eq(enemy.machine.current_name(), &"HitStun")


func test_poise_stays_host_side_and_the_staggered_flag_is_replicated() -> void:
	var enemy: Enemy = _enemy()
	var sync: MultiplayerSynchronizer = enemy.get_node("StateSync") as MultiplayerSynchronizer
	var paths: Array[String] = []
	for path: NodePath in sync.replication_config.get_properties():
		paths.append(str(path))
	assert_has(paths, ".:staggered", "the flag rides the existing enemy state sync")
	for path: String in paths:
		assert_false(path.contains("poise"), "poise is host only: %s" % path)
