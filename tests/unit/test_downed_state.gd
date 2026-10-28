extends GutTest
## Tests for scenes/player/states/downed.gd on the real player scene (W3-A5's
## state half, G13a2): a lethal hit with a teammate standing enters Downed and
## starts the 30 s bleed-out on the G13a1 clock (`DownedClock`), the clock
## running out ends in Dead, solo skips Downed for Dead at once, and the state
## refuses every exit but the revive (Idle) and the bleed-out (Dead). Owned by
## player-controller.
##
## The machine and the combat timers are stepped by hand and the bus events
## are recorded by named methods — no lambda connects, no awaits. The clock's
## own numbers are `test_downed.gd`'s; the revive hold's wiring is G13b1 and
## G13b2. The host ticks the clock from `Player._tick_combat_timers` because a
## downed player's machine is stopped (`Player.simulates` is false — pinned by
## test_player_sync.gd), so the tick is proven through the timer path too.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

const CLIENT_PEER: int = 2

var _player: Player
var _teammate: Player = null
var _health: Health
var _downs: Array[Player] = []
var _deaths: Array[Player] = []


func before_each() -> void:
	# A slow or hit-stop leaked from another file must not stretch the clocks.
	TimeManager.clear_source(TimeManager.HIT_STOP_SOURCE)
	TimeManager.clear_source(&"test")
	GameState.run = null
	NetworkManager.players.clear()
	_downs.clear()
	_deaths.clear()
	Events.player_downed.connect(_on_player_downed)
	Events.player_died.connect(_on_player_died)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.set_physics_process(false)
	_player.state_machine.set_physics_process(false)
	_health = _player.health as Health


func after_each() -> void:
	if Events.player_downed.is_connected(_on_player_downed):
		Events.player_downed.disconnect(_on_player_downed)
	if Events.player_died.is_connected(_on_player_died):
		Events.player_died.disconnect(_on_player_died)
	NetworkManager.players.clear()
	GameState.run = null
	TimeManager.clear_source(TimeManager.HIT_STOP_SOURCE)
	TimeManager.clear_source(&"test")


func _on_player_downed(who: Player) -> void:
	_downs.append(who)


func _on_player_died(who: Player) -> void:
	_deaths.append(who)


## A standing teammate registered the way PlayerSpawner does once a spawn has
## completed.
func _standing_teammate() -> Player:
	_teammate = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child_autofree(_teammate)
	_teammate.peer_id = CLIENT_PEER
	NetworkManager.players[CLIENT_PEER] = _teammate
	return _teammate


## Kills the player through the real damage path with a teammate standing, so
## the death lands in Downed.
func _down_the_player() -> void:
	_standing_teammate()
	_health.apply_damage(_lethal_hit())


func _lethal_hit() -> HitInfo:
	var hit := HitInfo.new()
	hit.final_damage = 9999
	return hit


# --- a lethal hit with a teammate standing enters Downed ---------------------


func test_a_lethal_hit_with_a_teammate_standing_enters_downed() -> void:
	_down_the_player()
	assert_true(_player.is_downed, "the player is down")
	assert_eq(_player.state_machine.current_name(), &"Downed", "the Downed state took the body")
	assert_almost_eq(_player.bleed_out_left, DownedClock.BLEED_OUT_SECONDS, 0.0001,
		"entry started the 30 s bleed-out on the G13a1 clock")
	assert_eq(_downs, [_player] as Array[Player], "one player_downed on the bus")
	assert_eq(_deaths, [] as Array[Player], "and nobody died")


func test_the_bleed_out_ticks_through_the_combat_timers_into_dead() -> void:
	_down_the_player()
	_player._tick_combat_timers(15.0)
	assert_eq(_player.state_machine.current_name(), &"Downed", "half the window is still down")
	assert_almost_eq(_player.bleed_out_left, 15.0, 0.0001)
	_player._tick_combat_timers(14.9999)
	assert_eq(_player.state_machine.current_name(), &"Downed", "one frame short")
	_player._tick_combat_timers(0.0002)
	assert_eq(_player.state_machine.current_name(), &"Dead", "30 s of bleed-out is Dead")
	assert_true(_player.is_dead)
	assert_false(_player.is_downed)
	assert_eq(_downs, [_player] as Array[Player], "the down happened once")
	assert_eq(_deaths, [_player] as Array[Player], "and the death followed the bleed-out")


# --- solo: downed is skipped, Dead immediately --------------------------------


func test_solo_skips_downed_and_dies_at_once() -> void:
	# No teammate registered at all.
	_health.apply_damage(_lethal_hit())
	assert_eq(_player.state_machine.current_name(), &"Dead", "solo never sees the Downed state")
	assert_true(_player.is_dead)
	assert_false(_player.is_downed)
	assert_eq(_player.bleed_out_left, 0.0, "no bleed-out clock ran")
	assert_eq(_deaths, [_player] as Array[Player], "one player_died")
	assert_eq(_downs, [] as Array[Player], "and no player_downed")


func test_a_downed_teammate_does_not_count_as_standing() -> void:
	var mate := _standing_teammate()
	mate.is_downed = true
	_health.apply_damage(_lethal_hit())
	assert_eq(_player.state_machine.current_name(), &"Dead",
		"the last player standing goes straight to Dead, not Downed")


# --- the state's contract -----------------------------------------------------


func test_downed_refuses_everything_but_revive_and_death() -> void:
	_down_the_player()
	assert_false(_player.state_machine.change_to(&"Move"))
	assert_false(_player.state_machine.change_to(&"Attack"))
	assert_false(_player.state_machine.change_to(&"Dodge"))
	assert_false(_player.state_machine.change_to(&"HitStun"))
	assert_false(_player.state_machine.change_to(&"HeavyCharge"))
	assert_eq(_player.state_machine.current_name(), &"Downed",
		"nothing but the revive or the bleed-out moved the body")


func test_a_revive_stands_the_player_back_up_out_of_downed() -> void:
	_down_the_player()
	_player._tick_combat_timers(10.0)
	# The host's revive application clears the flag, then the announce reaches
	# this player (`revived(by)`); NetworkManager's refusals are test_revive.gd's.
	_player.is_downed = false
	_player.revived.emit(_teammate)
	assert_eq(_player.state_machine.current_name(), &"Idle", "the revive stood them up")
	assert_false(_player.is_downed)
	assert_eq(_player.bleed_out_left, 0.0, "the clock stopped with the revive")
	assert_eq((_player.health as Health).current_hp, 40, "back at 40% HP")
	assert_true(_player.hurtbox.invulnerable, "the revive's moment of grace is up")


func test_a_dead_player_cannot_be_downed_again() -> void:
	_health.apply_damage(_lethal_hit())
	assert_false(_player.state_machine.change_to(&"Downed"), "Dead is not re-enterable as Downed")
	assert_eq(_player.state_machine.current_name(), &"Dead")


func test_the_downed_state_holds_the_body_still() -> void:
	_down_the_player()
	_player.velocity = Vector2(120.0, 0.0)
	_player.state_machine.physics_update(1.0 / 60.0)
	assert_eq(_player.velocity, Vector2.ZERO, "a downed player cannot move")
