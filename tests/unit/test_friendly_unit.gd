extends GutTest
## Tests for FriendlyUnit (SPEC-combat-core "Team", W5-A7): the unit is on the
## player side, a hit from it never lands on its owner, its lifetime runs in
## TimeManager-scaled time of its owner and frees it when spent, follow moves it
## toward the owner, and a copied swing hits enemies only. Owned by combat-core.
## Physics processing is off, so the tests drive advance() and the hitbox by hand.
## The TimeManager source is cleared after each test.

const TIME_SOURCE: StringName = &"test_friendly_unit_slow"
const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const CLIENT_PORT: int = 7791

var _unit: FriendlyUnit
var _default_api: MultiplayerAPI = null
var _client_peer: ENetMultiplayerPeer = null


func after_each() -> void:
	TimeManager.clear_source(TIME_SOURCE)
	if _client_peer != null:
		get_tree().set_multiplayer(_default_api, get_path())
		_client_peer.close()
		_client_peer = null


## A unit with physics off, in the tree, with no owner unless one is given.
func _unit_for(seconds: float, owner_node: Player = null) -> void:
	_unit = FriendlyUnit.new()
	_unit.set_physics_process(false)
	_unit.setup(owner_node, seconds)
	add_child_autofree(_unit)


func _owner_in_tree(at: Vector2) -> Player:
	var owner_node := load(PLAYER_SCENE).instantiate() as Player
	add_child_autofree(owner_node)
	owner_node.global_position = at
	return owner_node


func _hurtbox_on(team: Team.Kind) -> RecordingHurtbox:
	var hurtbox := RecordingHurtbox.new()
	hurtbox.team = team
	add_child_autofree(hurtbox)
	return hurtbox


func test_the_unit_is_on_the_player_side_and_has_health_and_a_hurtbox() -> void:
	_unit_for(5.0)
	assert_eq(FriendlyUnit.TEAM, Team.Kind.PLAYER, "the unit is on the player side")
	var hurtbox := _unit.get_node_or_null("Hurtbox") as Hurtbox
	assert_not_null(hurtbox, "the unit has a Hurtbox child")
	if hurtbox != null:
		assert_eq(hurtbox.team, Team.Kind.PLAYER, "its Hurtbox is on the player side")
	assert_not_null(_unit.get_node_or_null("Health") as Health, "the unit has a Health child")


func test_a_hit_from_the_unit_does_not_land_on_its_owner() -> void:
	var owner_node := _owner_in_tree(Vector2.ZERO)
	var owner_hurtbox := owner_node.get_node("Hurtbox") as Hurtbox
	var owner_health := owner_node.get_node("Health") as Health
	var hp_before: int = owner_health.current_hp
	_unit_for(5.0, owner_node)
	var lethal := HitInfo.new()
	lethal.base_damage = 9999.0
	var hitbox := _unit.strike_with(lethal, 40.0, 0.2)
	assert_false(hitbox.try_hit(owner_hurtbox), "a player-side hitbox does not hurt the owner's hurtbox")
	assert_eq(owner_health.current_hp, hp_before, "the owner keeps its HP")


func test_a_hit_from_the_unit_lands_on_an_enemy() -> void:
	var enemy := _hurtbox_on(Team.Kind.ENEMY)
	_unit_for(5.0)
	var hitbox := _unit.strike_with(HitInfo.new(), 40.0, 0.2)
	assert_true(hitbox.try_hit(enemy), "a player-side hitbox hurts an enemy")
	assert_eq(enemy.received.size(), 1, "the enemy is handed one hit")


func test_a_swing_goes_dead_when_its_active_window_ends() -> void:
	var enemy := _hurtbox_on(Team.Kind.ENEMY)
	_unit_for(5.0)
	var hitbox := _unit.strike_with(HitInfo.new(), 40.0, 0.2)
	_unit.advance(0.25)
	assert_false(hitbox.try_hit(enemy), "the swing hits nothing after its window")


func test_the_unit_expires_and_frees_itself_when_its_lifetime_is_spent() -> void:
	_unit_for(1.0)
	_unit.advance(0.5)
	assert_false(_unit.is_queued_for_deletion(), "the unit is alive before its lifetime is spent")
	_unit.advance(0.6)
	assert_true(_unit.is_queued_for_deletion(), "the unit frees once its lifetime is spent")


## Makes the tree's multiplayer a client (an unconnected ENet client peer), so
## `multiplayer.is_server()` is false. Restored in after_each.
func _become_client() -> void:
	_default_api = get_multiplayer()
	_client_peer = ENetMultiplayerPeer.new()
	assert_eq(_client_peer.create_client("127.0.0.1", CLIENT_PORT), OK, "the client peer opens")
	var client_api := SceneMultiplayer.new()
	client_api.multiplayer_peer = _client_peer
	get_tree().set_multiplayer(client_api, get_path())


func test_a_client_copy_keeps_its_unit_because_the_host_frees_it() -> void:
	_become_client()
	assert_false(multiplayer.is_server(), "the test peer is a client")
	_unit_for(1.0)
	_unit.advance(5.0)
	assert_false(_unit.is_queued_for_deletion(), "a client's copy does not run the lifetime")


func test_a_unit_whose_health_runs_out_frees_itself() -> void:
	_unit_for(5.0)
	var hit := HitInfo.new()
	hit.base_damage = 9999.0
	var hurtbox := _unit.get_node("Hurtbox") as Hurtbox
	hurtbox.receive(hit)
	assert_true(_unit.is_queued_for_deletion(), "a unit that dies is freed")


func test_the_lifetime_runs_in_the_owners_time_scale() -> void:
	var owner_node := _owner_in_tree(Vector2.ZERO)
	TimeManager.set_entity_scale(owner_node, 0.5, 10.0, TIME_SOURCE)
	_unit_for(1.0, owner_node)
	_unit.advance(1.5)
	assert_false(_unit.is_queued_for_deletion(), "a half-speed owner stretches the unit's life")
	TimeManager.clear_source(TIME_SOURCE)


func test_follow_moves_the_unit_toward_its_owner() -> void:
	var owner_node := _owner_in_tree(Vector2(300.0, 0.0))
	_unit_for(5.0, owner_node)
	_unit.global_position = Vector2.ZERO
	_unit.advance(0.1)
	assert_gt(_unit.global_position.x, 0.0, "the unit moves toward the owner")
	assert_lt(_unit.global_position.x, 300.0, "the unit does not jump onto the owner")


func test_follow_off_keeps_the_unit_where_it_spawned() -> void:
	var owner_node := _owner_in_tree(Vector2(300.0, 0.0))
	_unit_for(5.0, owner_node)
	_unit.follow_owner = false
	_unit.global_position = Vector2.ZERO
	_unit.advance(0.1)
	assert_eq(_unit.global_position, Vector2.ZERO, "a unit with follow off stays put")


func test_the_unit_stands_still_when_it_is_already_close_to_its_owner() -> void:
	var owner_node := _owner_in_tree(Vector2(10.0, 0.0))
	_unit_for(5.0, owner_node)
	_unit.global_position = Vector2.ZERO
	_unit.advance(0.1)
	assert_eq(_unit.global_position, Vector2.ZERO, "a unit inside the follow distance does not move")


func test_with_no_peers_the_position_is_not_sent_and_advance_runs_clean() -> void:
	var owner_node := _owner_in_tree(Vector2(300.0, 0.0))
	_unit_for(5.0, owner_node)
	assert_eq(multiplayer.get_peers().size(), 0, "the test runs with no peers")
	assert_false(_unit._send_position(), "with no peers the position is not sent")
	_unit.global_position = Vector2.ZERO
	_unit.advance(0.1)
	assert_gt(_unit.global_position.x, 0.0, "advance still runs the follow step with no peers")
	assert_false(_unit.is_queued_for_deletion(), "advance with no peers keeps the unit alive")
