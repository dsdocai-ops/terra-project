extends GutTest
## The elite affixes run on the host only (SPEC-enemies-ai "Elites", W4-A1 part 2
## follow-up). Enemy and Hurtbox gate every affix path on multiplayer.is_server().
## This file puts a client-side SceneMultiplayer over the test node, so the enemy
## and its hurtbox see a non-host peer, then checks the affix paths stay still.
## Owned by enemies-ai. Sync: none; the affix runs host-side only, and a client
## copy of the elite is driven by StateSync, not by these paths.

const ENEMY_SCENE := "res://scenes/enemies/enemy_base.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const ELITE_KIND: StringName = &"hollow_miner"
## Nothing listens here. The client peer only has to exist, not connect.
const CLIENT_PORT := 7811

var _default_api: MultiplayerAPI = null
var _client_peer: ENetMultiplayerPeer = null
## Nodes this file added under the client API. They are freed before the API is
## restored, so each one leaves the API it joined (a late free logs engine errors).
var _owned: Array[Node] = []


func before_each() -> void:
	_default_api = get_multiplayer()
	_client_peer = ENetMultiplayerPeer.new()
	assert_eq(_client_peer.create_client("127.0.0.1", CLIENT_PORT), OK, "the client peer opens")
	var client_api := SceneMultiplayer.new()
	client_api.multiplayer_peer = _client_peer
	get_tree().set_multiplayer(client_api, get_path())


func after_each() -> void:
	for node: Node in _owned:
		node.free()
	_owned.clear()
	get_tree().set_multiplayer(_default_api, get_path())
	_client_peer.close()


func _adopt(node: Node) -> void:
	add_child(node)
	_owned.append(node)


func _spawn_elite(affix: EliteAffix.Affix) -> Enemy:
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Enemy
	assert_true(enemy.setup(ELITE_KIND, true, affix), "the elite data loads")
	_adopt(enemy)
	return enemy


func test_the_fake_peer_is_a_client() -> void:
	assert_false(multiplayer.is_server(), "the test peer is not the host")


func test_a_client_elite_never_steps_its_blink_timer() -> void:
	var enemy := _spawn_elite(EliteAffix.Affix.TELEPORTING)
	var target := Node2D.new()
	_adopt(target)
	target.global_position = Vector2(100, 0)
	enemy.target = target
	enemy.global_position = Vector2.ZERO
	enemy._physics_process(AffixTeleporting.BLINK_SECONDS)
	enemy._physics_process(AffixTeleporting.TELEGRAPH_SECONDS + 0.1)
	assert_almost_eq(enemy.global_position.x, 0.0, 0.001, "a client elite never blinks")
	assert_eq(enemy.telegraph_progress, -1.0, "and never starts a telegraph")


func test_a_client_elite_takes_no_lethal_hit_so_no_death_affix_runs() -> void:
	var enemy := _spawn_elite(EliteAffix.Affix.SPLITTING)
	var hp: int = enemy.health.current_hp
	assert_false(enemy.apply_hit(9999), "a client cannot apply a hit")
	assert_eq(enemy.health.current_hp, hp, "the elite keeps its HP")
	assert_false(enemy.health.is_dead, "so it does not die and no split runs")


func test_a_client_hurtbox_does_not_run_the_shield_absorb() -> void:
	var enemy := _spawn_elite(EliteAffix.Affix.SHIELDED)
	var shield := enemy.affix_behavior as AffixShielded
	var hurtbox := enemy.get_node("Hurtbox") as Hurtbox
	var hit := HitInfo.new()
	hit.base_damage = 5.0
	assert_false(hurtbox.receive(hit), "a client hurtbox takes no hit")
	assert_eq(shield.hits_left, AffixShielded.SHIELD_MAX_HITS, "the shield count is untouched")


func test_a_client_hasted_elite_gets_no_speed_modifier() -> void:
	var enemy := _spawn_elite(EliteAffix.Affix.HASTED)
	assert_almost_eq(enemy.move_speed(), enemy.data.move_speed, 0.001, "no +40 % move speed on a client")
	assert_almost_eq(enemy.attack_speed(), 1.0, 0.001, "no +40 % attack speed on a client")


func test_a_client_vampiric_elite_does_not_heal_on_a_landed_hit() -> void:
	var enemy := _spawn_elite(EliteAffix.Affix.VAMPIRIC)
	enemy.health.current_hp = 5
	enemy.on_dealt_damage(10)
	assert_eq(enemy.health.current_hp, 5, "a client elite never heals from its own hit")


func test_a_client_explosive_blast_does_not_hit_a_player_in_radius() -> void:
	var enemy := _spawn_elite(EliteAffix.Affix.EXPLOSIVE)
	enemy.global_position = Vector2.ZERO
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	_adopt(player)
	player.global_position = Vector2(AffixExplosive.BLAST_RADIUS - 4.0, 0.0)
	player.add_to_group(&"player")
	var hp: int = player.health.current_hp
	enemy.affix_behavior.on_death(enemy, HitInfo.new())
	await get_tree().create_timer(AffixExplosive.TELEGRAPH_SECONDS + 0.2).timeout
	assert_eq(player.health.current_hp, hp, "the blast is refused on a client, so the player is untouched")
