extends GutTest
## The pure `Targeting.pick` (SPEC-enemies-ai "Targeting"): nearest by
## default, a taunt overrides, an untargetable candidate is invisible and
## empty-handed picks drop aggro, the spread joins the player the pack is not
## focused on (fewest `targeters` inside the spread window), and the current
## target is kept while it stays within that window. The closing cases run the
## real `Enemy.pick_target` through `Targeting` with real players in
## `NetworkManager.players`. Owned by enemies-ai.

const ENEMY_SCENE := "res://scenes/enemies/enemy_base.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const ORIGIN := Vector2.ZERO


func _c(position: Vector2, alive: bool = true, untargetable: bool = false, taunting: bool = false, node: Node2D = null) -> Targeting.Candidate:
	var c := Targeting.Candidate.new()
	c.position = position
	c.alive = alive
	c.untargetable = untargetable
	c.taunting = taunting
	c.node = node
	return c


# --- nearest by default -------------------------------------------------------


func test_the_nearest_candidate_wins() -> void:
	var picked := Targeting.pick(ORIGIN, null, [_c(Vector2(300, 0)), _c(Vector2(100, 0)), _c(Vector2(200, 0))])
	assert_eq(picked.position, Vector2(100, 0))


func test_an_equidistant_tie_breaks_by_input_order() -> void:
	var picked := Targeting.pick(ORIGIN, null, [_c(Vector2(0, 100)), _c(Vector2(100, 0))])
	assert_eq(picked.position, Vector2(0, 100), "both 100 px away: the first listed wins, deterministically")


# --- dead and downed are not targets -------------------------------------------


func test_a_dead_candidate_is_skipped() -> void:
	var picked := Targeting.pick(ORIGIN, null, [_c(Vector2(50, 0), false), _c(Vector2(300, 0))])
	assert_eq(picked.position, Vector2(300, 0))


func test_a_downed_player_is_skipped() -> void:
	var picked := Targeting.pick(ORIGIN, null, [_c(Vector2(50, 0), false, false, false), _c(Vector2(300, 0))])
	assert_eq(picked.position, Vector2(300, 0))


# --- untargetable (Smoke Step / Smoke Bomb / Vanish / Ghost Wrap) ----------------


func test_an_untargetable_candidate_is_invisible_to_the_pick() -> void:
	var picked := Targeting.pick(ORIGIN, null, [_c(Vector2(50, 0), true, true), _c(Vector2(300, 0))])
	assert_eq(picked.position, Vector2(300, 0), "the nearer but hidden candidate is never chosen")


func test_nothing_targetable_drops_aggro() -> void:
	assert_null(Targeting.pick(ORIGIN, null, [_c(Vector2(50, 0), true, true), _c(Vector2(60, 0), false)]))


func test_an_empty_candidate_list_picks_nothing() -> void:
	assert_null(Targeting.pick(ORIGIN, null, []))


# --- taunt overrides ------------------------------------------------------------


func test_a_taunt_wins_over_distance() -> void:
	var picked := Targeting.pick(ORIGIN, null, [_c(Vector2(50, 0)), _c(Vector2(400, 0), true, false, true)])
	assert_eq(picked.position, Vector2(400, 0), "the taunting candidate wins from anywhere")


func test_the_nearest_taunt_wins_when_several_taunt() -> void:
	var picked := Targeting.pick(ORIGIN, null, [_c(Vector2(300, 0), true, false, true), _c(Vector2(200, 0), true, false, true), _c(Vector2(40, 0))])
	assert_eq(picked.position, Vector2(200, 0))


# --- spread aggro ---------------------------------------------------------------


func test_the_current_target_is_kept_while_it_stays_near_the_nearest() -> void:
	var current: Node2D = autofree(Node2D.new())
	var nearer := _c(Vector2(100, 0))
	var held := _c(Vector2(118, 0), true, false, false, current)
	var picked := Targeting.pick(ORIGIN, current, [nearer, held])
	assert_eq(picked, held, "1.18x the nearest is inside the 1.25x spread window: no switch")


func test_a_current_out_of_the_spread_window_falls_to_the_nearest() -> void:
	var current: Node2D = autofree(Node2D.new())
	var held := _c(Vector2(190, 0), true, false, false, current)
	var picked := Targeting.pick(ORIGIN, current, [_c(Vector2(100, 0)), held])
	assert_eq(picked.position, Vector2(100, 0), "1.9x the nearest is too far to keep")


func test_a_current_that_died_is_dropped() -> void:
	var current: Node2D = autofree(Node2D.new())
	var held := _c(Vector2(118, 0), false, false, false, current)
	var picked := Targeting.pick(ORIGIN, current, [_c(Vector2(100, 0)), held])
	assert_eq(picked.position, Vector2(100, 0))


func test_a_taunt_beats_the_spread() -> void:
	var current: Node2D = autofree(Node2D.new())
	var held := _c(Vector2(100, 0), true, false, false, current)
	var picked := Targeting.pick(ORIGIN, current, [held, _c(Vector2(400, 0), true, false, true)])
	assert_eq(picked.position, Vector2(400, 0), "taunting wins unless taunting")


# --- spread aggro: the pack's load -----------------------------------------------


func test_a_fresh_enemy_joins_the_player_the_pack_is_not_focused_on() -> void:
	var focused := _c(Vector2(100, 0))
	focused.targeters = 2
	var open := _c(Vector2(110, 0))
	var picked := Targeting.pick(ORIGIN, null, [focused, open])
	assert_eq(picked, open, "the open player inside the spread window wins over the focused nearer one")


func test_an_enemy_leaves_a_focused_current_target_for_the_open_one() -> void:
	var current: Node2D = autofree(Node2D.new())
	var held := _c(Vector2(100, 0), true, false, false, current)
	held.targeters = 1
	var open := _c(Vector2(115, 0))
	var picked := Targeting.pick(ORIGIN, current, [held, open])
	assert_eq(picked, open, "another enemy joined the current target: switch to the open one")


func test_the_current_target_holds_when_nobody_else_carries_it() -> void:
	var current: Node2D = autofree(Node2D.new())
	var nearer := _c(Vector2(100, 0))
	nearer.targeters = 1
	var held := _c(Vector2(118, 0), true, false, false, current)
	var picked := Targeting.pick(ORIGIN, current, [nearer, held])
	assert_eq(picked, held, "the other player is focused instead: keep the current one")


func test_the_load_only_competes_inside_the_spread_window() -> void:
	var focused := _c(Vector2(100, 0))
	focused.targeters = 3
	var open := _c(Vector2(200, 0))
	var picked := Targeting.pick(ORIGIN, null, [focused, open])
	assert_eq(picked, focused, "the open player is 2x the nearest: outside the window, the focused nearest wins")


func test_an_equal_load_breaks_the_tie_by_distance() -> void:
	var a := _c(Vector2(100, 0))
	a.targeters = 1
	var b := _c(Vector2(110, 0))
	b.targeters = 1
	var picked := Targeting.pick(ORIGIN, null, [b, a])
	assert_eq(picked, a, "same load: the nearer one wins")


func test_a_taunt_beats_the_pack_load() -> void:
	var focused := _c(Vector2(100, 0))
	focused.targeters = 5
	var taunted := _c(Vector2(400, 0), true, false, true)
	var picked := Targeting.pick(ORIGIN, null, [focused, taunted])
	assert_eq(picked, taunted, "the spec: one player is not focused unless taunting")


# --- the candidate adapter --------------------------------------------------------


class TargetDouble extends Node2D:
	var is_dead: bool = false
	var is_downed: bool = false
	var untargetable: bool = false
	var taunting: bool = false


func test_the_adapter_reads_every_flag_duck_typed() -> void:
	var a: TargetDouble = autofree(TargetDouble.new())
	a.is_downed = true
	a.taunting = true
	a.global_position = Vector2(30, 40)
	var c := Targeting.candidate(a)
	assert_eq(c.node, a)
	assert_eq(c.position, Vector2(30, 40))
	assert_false(c.alive, "is_downed reads as not alive")
	assert_true(c.taunting)
	assert_false(c.untargetable)

	var b: TargetDouble = autofree(TargetDouble.new())
	b.is_dead = true
	b.untargetable = true
	assert_false(Targeting.candidate(b).alive, "is_dead reads as not alive")
	assert_true(Targeting.candidate(b).untargetable)

	var plain: Node2D = autofree(Node2D.new())
	assert_true(Targeting.candidate(plain).alive, "a node without the properties reads alive and calm")
	assert_false(Targeting.candidate(plain).untargetable)
	assert_false(Targeting.candidate(plain).taunting)


# --- the enemy's pick_target routes through Targeting ------------------------------


var _enemy: Enemy
var _player_a: Player
var _player_b: Player


func before_each() -> void:
	_enemy = (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	assert_true(_enemy.setup(&"hollow_miner"), "hollow_miner data loads")
	add_child_autofree(_enemy)
	_enemy.global_position = ORIGIN
	_player_a = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_player_b = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player_a)
	add_child_autofree(_player_b)


func after_each() -> void:
	NetworkManager.players.erase(1)
	NetworkManager.players.erase(2)


func _wire_players() -> void:
	NetworkManager.players[1] = _player_a
	NetworkManager.players[2] = _player_b


func test_pick_target_returns_the_nearest_player() -> void:
	_wire_players()
	_player_a.global_position = Vector2(240, 0)
	_player_b.global_position = Vector2(120, 0)
	assert_eq(_enemy.pick_target(), _player_b)


func test_pick_target_skips_a_downed_player() -> void:
	_wire_players()
	_player_a.global_position = Vector2(50, 0)
	_player_b.global_position = Vector2(120, 0)
	_player_a.is_downed = true
	assert_eq(_enemy.pick_target(), _player_b, "the downed nearer player is not targeted")


func test_pick_target_skips_an_untargetable_player() -> void:
	_wire_players()
	_player_a.global_position = Vector2(50, 0)
	_player_b.global_position = Vector2(120, 0)
	_player_a.untargetable = true
	assert_eq(_enemy.pick_target(), _player_b, "the hidden nearer player is not targeted")


func test_pick_target_drops_aggro_when_nobody_is_targetable() -> void:
	_wire_players()
	_player_a.global_position = Vector2(50, 0)
	_player_b.global_position = Vector2(120, 0)
	_player_a.untargetable = true
	_player_b.is_dead = true
	assert_null(_enemy.pick_target())


func test_pick_target_keeps_its_current_target_inside_the_spread_window() -> void:
	_wire_players()
	_player_a.global_position = Vector2(100, 0)
	_player_b.global_position = Vector2(118, 0)
	_enemy.target = _player_b
	assert_eq(_enemy.pick_target(), _player_b, "the current target holds against a mildly nearer player")


func test_pick_target_spreads_the_pack_across_the_players() -> void:
	_wire_players()
	_player_a.global_position = Vector2(100, 0)
	_player_b.global_position = Vector2(110, 0)
	var other := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	assert_true(other.setup(&"hollow_miner"))
	add_child_autofree(other)
	other.global_position = Vector2(90, 0)
	other.target = _player_a
	assert_eq(_enemy.pick_target(), _player_b, "the pack is focused on player_a: the fresh enemy joins player_b")


func test_pick_target_does_not_count_its_own_hold_as_load() -> void:
	_wire_players()
	_player_a.global_position = Vector2(100, 0)
	_player_b.global_position = Vector2(110, 0)
	_enemy.target = _player_a
	assert_eq(_enemy.pick_target(), _player_a, "only this enemy holds player_a: the hysteresis keeps it")
