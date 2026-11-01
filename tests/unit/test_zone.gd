extends GutTest
## Tests for Zone (SPEC-abilities "Zone"): a strike is a copy of the template onto
## an opposing hurtbox only, ticks come on the interval for the duration, and the
## clock runs in TimeManager-scaled time. Owned by abilities. The zone stands alone
## with no overlaps, so the tests strike hurtboxes directly and drive advance() by
## hand. Physics processing is off. The TimeManager source is cleared after each
## test.

const TIME_SOURCE: StringName = &"test_zone_slow"
const CLIENT_PORT: int = 7815

var _zone: Zone
var _template: HitInfo


func before_each() -> void:
	_template = HitInfo.new()
	_template.base_damage = 10.0
	_template.tags = [&"ability", &"toxic_cloud"]


func after_each() -> void:
	TimeManager.clear_source(TIME_SOURCE)


## A zone on the player side, configured and in the tree, with physics off.
func _zone_for(seconds: float, interval: float, time_node: Node = null) -> void:
	_zone = Zone.new()
	_zone.set_physics_process(false)
	_zone.configure(_template, seconds, interval, time_node)
	add_child_autofree(_zone)


func _enemy_hurtbox() -> RecordingHurtbox:
	var hurtbox := RecordingHurtbox.new()
	hurtbox.team = Team.Kind.ENEMY
	add_child_autofree(hurtbox)
	return hurtbox


func test_a_strike_hands_an_enemy_hurtbox_a_copy_of_the_template() -> void:
	_zone_for(2.0, 0.5)
	var hurtbox := _enemy_hurtbox()
	assert_true(_zone.strike(hurtbox), "an enemy hurtbox takes the hit")
	assert_eq(hurtbox.received.size(), 1, "one hit lands")
	var hit: HitInfo = hurtbox.received[0]
	assert_ne(hit, _template, "the hurtbox gets a copy, not the template")
	assert_almost_eq(hit.base_damage, 10.0, 0.001, "the copy keeps the base damage")
	assert_true(hit.tags.has(&"toxic_cloud"), "the copy keeps the ability tags")


func test_a_zone_with_no_template_strikes_nothing() -> void:
	_zone = Zone.new()
	_zone.set_physics_process(false)
	add_child_autofree(_zone)
	var hurtbox := _enemy_hurtbox()
	assert_false(_zone.strike(hurtbox), "a zone with no template hands out no hit")
	assert_eq(hurtbox.received.size(), 0, "no hit lands from a zone with no template")


func test_a_strike_skips_a_hurtbox_on_the_zones_own_side() -> void:
	_zone_for(2.0, 0.5)
	var own_side := RecordingHurtbox.new()
	own_side.team = Team.Kind.PLAYER
	add_child_autofree(own_side)
	assert_false(_zone.strike(own_side), "a player-side hurtbox is not struck")
	assert_eq(own_side.received.size(), 0, "no hit lands on the zone's own side")


func test_ticks_come_on_the_interval_and_the_zone_frees_when_spent() -> void:
	_zone_for(2.0, 0.5)
	_zone.advance(0.5)
	assert_eq(_zone.ticks_done, 1, "the first tick is due after one interval")
	_zone.advance(0.5)
	assert_eq(_zone.ticks_done, 2, "the second tick is due one interval later")
	_zone.advance(1.0)
	assert_eq(_zone.ticks_done, 4, "two more ticks fill the 2 s duration")
	assert_true(_zone.is_queued_for_deletion(), "the zone frees when its duration is spent")


func test_the_clock_runs_in_time_manager_scaled_time() -> void:
	var slow := Node2D.new()
	add_child_autofree(slow)
	TimeManager.set_entity_scale(slow, 0.5, 10.0, TIME_SOURCE)
	_zone_for(2.0, 0.5, slow)
	_zone.advance(0.5)
	_zone.advance(0.5)
	assert_eq(_zone.ticks_done, 1, "at half speed two 0.5 s steps are one 0.5 s of zone time")


func test_set_radius_gives_the_zone_a_circle_of_that_radius() -> void:
	_zone = Zone.new()
	_zone.set_physics_process(false)
	_zone.set_radius(30.0)
	_zone.configure(_template, 1.0, 0.5, null)
	add_child_autofree(_zone)
	var shape_node := _zone.get_node_or_null("Shape") as CollisionShape2D
	assert_not_null(shape_node, "the zone has one collision shape")
	var circle: CircleShape2D = null
	if shape_node != null:
		circle = shape_node.shape as CircleShape2D
	assert_not_null(circle, "the shape is a circle")
	if circle != null:
		assert_almost_eq(circle.radius, 30.0, 0.001, "the circle is the radius asked for")


func test_a_zero_radius_is_raised_to_the_minimum_circle() -> void:
	_zone = Zone.new()
	_zone.set_physics_process(false)
	_zone.set_radius(0.0)
	add_child_autofree(_zone)
	var circle := _zone.get_node("Shape").shape as CircleShape2D
	assert_almost_eq(circle.radius, Zone.MIN_RADIUS, 0.001, "a zero radius becomes the minimum circle, not a point")


func test_a_client_zone_strikes_no_hurtbox() -> void:
	# The zone is made on the host API, then its strike is called under a client API,
	# so the host guard in strike is the one that refuses the hit. Restored after.
	_zone_for(2.0, 0.5)
	var hurtbox := _enemy_hurtbox()
	var default_api: MultiplayerAPI = get_multiplayer()
	var client_peer := ENetMultiplayerPeer.new()
	assert_eq(client_peer.create_client("127.0.0.1", CLIENT_PORT), OK, "the client peer opens")
	var client_api := SceneMultiplayer.new()
	client_api.multiplayer_peer = client_peer
	get_tree().set_multiplayer(client_api, get_path())
	var struck: bool = _zone.strike(hurtbox)
	get_tree().set_multiplayer(default_api, get_path())
	client_peer.close()
	assert_false(struck, "a client's zone strikes nothing")
	assert_eq(hurtbox.received.size(), 0, "no hit lands from a client's zone")
