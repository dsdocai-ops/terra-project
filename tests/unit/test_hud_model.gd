extends GutTest
## Unit tests for HudModel, the adapter that turns replicated player state
## into the typed properties the HUD widgets bind to (W2-B5). Owned by
## ui-hud. Players come from the real player scene with a FakeHealth double
## hung on the Health node standing in for Dev A's Health component (W2-A1);
## HudModel reads HP duck-typed, so the swap-in is seamless.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FAKE_HEALTH_SCRIPT := "res://tests/helpers/fake_health.gd"

var _players: Dictionary[int, Player] = {}
var _changed_count: int = 0


func before_each() -> void:
	_players.clear()
	_changed_count = 0


func _make_player(peer_id: int, slot: int, current_hp: int, max_hp: int, downed: bool, with_health: bool = true) -> Player:
	var player: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	if with_health:
		var health := player.get_node("Health") as Node
		health.set_script(load(FAKE_HEALTH_SCRIPT))
		health.current_hp = current_hp
		health.max_hp = max_hp
	player.peer_id = peer_id
	player.slot = slot
	player.is_downed = downed
	player.name = "Player%d" % peer_id
	add_child_autofree(player)
	_players[peer_id] = player
	return player


func _make_model() -> HudModel:
	var model := HudModel.new()
	model.bind(func() -> Dictionary[int, Player]: return _players)
	return model


func _on_changed() -> void:
	_changed_count += 1


# Local player HP ratio

func test_local_hp_ratio_comes_from_the_health_component() -> void:
	_make_player(1, 0, 40, 100, false)
	var model := _make_model()
	model.refresh(1)
	assert_eq(model.local_hp_ratio, 0.4)
	assert_false(model.local_is_downed)


func test_local_hp_ratio_clamps_at_zero() -> void:
	_make_player(1, 0, 0, 100, false)
	var model := _make_model()
	model.refresh(1)
	assert_eq(model.local_hp_ratio, 0.0)


func test_cannot_go_above_full() -> void:
	_make_player(1, 0, 120, 100, false)
	var model := _make_model()
	model.refresh(1)
	assert_eq(model.local_hp_ratio, 1.0)


func test_missing_health_component_falls_back_to_a_full_bar() -> void:
	_make_player(1, 0, 0, 0, false, false)
	var model := _make_model()
	model.refresh(1)
	assert_eq(model.local_hp_ratio, 1.0, "Health has not landed: full bar placeholder")


func test_downed_state_is_exposed() -> void:
	_make_player(1, 0, 20, 100, true)
	var model := _make_model()
	model.refresh(1)
	assert_true(model.local_is_downed)


func test_no_players_yields_a_full_local_bar() -> void:
	var model := _make_model()
	model.refresh(1)
	assert_eq(model.local_hp_ratio, 1.0)
	assert_true(model.teammates.is_empty())


# Teammate bars

func test_teammates_exclude_the_local_player_and_copy_state() -> void:
	_make_player(1, 0, 50, 100, false)
	_make_player(2, 1, 10, 100, true)
	_make_player(3, 2, 100, 100, false)
	var model := _make_model()
	model.refresh(1)
	assert_eq(model.teammates.size(), 2)
	var second: HudModel.HudTeammate = model.teammates[0]
	assert_eq(second.peer_id, 2)
	assert_eq(second.display_name, "Player2", "name comes from the replicated player node")
	assert_eq(second.slot, 1)
	assert_eq(second.hp_ratio, 0.1)
	assert_true(second.is_downed, "downed state is copied to the teammate bar")
	var third: HudModel.HudTeammate = model.teammates[1]
	assert_eq(third.peer_id, 3)
	assert_eq(third.hp_ratio, 1.0)


func test_teammate_order_follows_registry_order() -> void:
	_make_player(3, 0, 100, 100, false)
	_make_player(1, 1, 100, 100, false)
	_make_player(2, 2, 100, 100, false)
	var model := _make_model()
	model.refresh(1)
	assert_eq(model.teammates.size(), 2)
	assert_eq(model.teammates[0].peer_id, 3, "host join order decides bar order")


func test_refresh_emits_changed() -> void:
	_make_player(1, 0, 100, 100, false)
	var model := _make_model()
	model.changed.connect(_on_changed)
	model.refresh(1)
	model.refresh(1)
	assert_eq(_changed_count, 2)


# Weapon slots

func test_weapon_slots_start_with_two_placeholders() -> void:
	var model := _make_model()
	assert_eq(model.weapon_slots.size(), HudModel.WEAPON_SLOT_COUNT, "two slots for the two weapons")
	assert_eq(model.weapon_slots[0].slot_index, 0)
	assert_eq(model.weapon_slots[1].slot_index, 1)
	assert_eq(model.weapon_slots[0].display_name, "-", "placeholder until WeaponData lands")
	assert_false(model.weapon_slots[0].active)
	assert_eq(model.weapon_slots[0].cooldown_fraction, 0.0)


# Cooldown-fraction math

func test_cooldown_fraction_math() -> void:
	assert_eq(HudModel.cooldown_fraction(2.5, 5.0), 0.5)
	assert_eq(HudModel.cooldown_fraction(5.0, 5.0), 1.0)
	assert_eq(HudModel.cooldown_fraction(0.0, 5.0), 0.0)
	assert_eq(HudModel.cooldown_fraction(-1.0, 5.0), 0.0, "clamped at zero")
	assert_eq(HudModel.cooldown_fraction(7.0, 5.0), 1.0, "clamped at one")
	assert_eq(HudModel.cooldown_fraction(2.0, 0.0), 0.0, "no total means no cooldown")


func test_set_weapon_cooldown_updates_the_slot_and_emits_changed() -> void:
	var model := _make_model()
	model.changed.connect(_on_changed)
	model.set_weapon_cooldown(1, 1.5, 3.0)
	assert_eq(model.weapon_slots[1].cooldown_fraction, 0.5)
	assert_eq(_changed_count, 1)


func test_set_weapon_active_marks_exactly_one_slot() -> void:
	var model := _make_model()
	model.set_weapon_active(0)
	assert_true(model.weapon_slots[0].active)
	assert_false(model.weapon_slots[1].active)
	model.set_weapon_active(1)
	assert_false(model.weapon_slots[0].active)
	assert_true(model.weapon_slots[1].active)


# Floor label

func test_floor_label_defaults_to_a_placeholder() -> void:
	var model := _make_model()
	assert_eq(model.floor_label, "FLOOR -")


func test_set_floor_label() -> void:
	var model := _make_model()
	model.changed.connect(_on_changed)
	model.set_floor_label("FLOOR 3")
	assert_eq(model.floor_label, "FLOOR 3")
	assert_eq(_changed_count, 1)

# Run state: currencies, relics, weapon names

var _run: RunState = null


func _bound_run() -> RunState:
	return _run


func test_run_values_are_zero_outside_a_run() -> void:
	var model := _make_model()
	model.bind_run(_bound_run)
	model.refresh(1)
	assert_eq(model.gold, 0)
	assert_eq(model.ore_total, 0)
	assert_true(model.relics.is_empty())


func test_currencies_and_relics_come_from_the_run() -> void:
	_run = RunState.new(5, 1)
	_run.shared_gold = 1240
	_run.shared_ore = {&"copper": 10, &"iron": 8}
	var mine := RunPlayerState.new(1)
	mine.echo_shards_earned = 6
	mine.weapon_ids = [&"pickaxe"]
	mine.relics = [&"ember_boots", &"ember_boots"]
	_run.add_player(mine)
	var model := _make_model()
	model.bind_run(_bound_run)
	model.refresh(1)
	assert_eq(model.gold, 1240)
	assert_eq(model.ore_total, 18)
	assert_eq(model.echo_shards, 6)
	assert_eq(model.relics.size(), 1, "a repeated relic is one entry")
	assert_eq(model.relics[0].stacks, 2)
	assert_eq(model.weapon_slots[0].display_name, "Pickaxe")
	assert_eq(model.weapon_slots[1].display_name, "-")
	_run = null


func test_local_hp_numbers_are_exposed() -> void:
	_make_player(1, 0, 40, 100, false)
	var model := _make_model()
	model.refresh(1)
	assert_eq(model.local_hp_current, 40)
	assert_eq(model.local_hp_max, 100)
