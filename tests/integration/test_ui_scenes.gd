extends GutTest
## Integration: the HUD scene instantiates over the world flow and renders the
## typed HudModel state. Owned by ui-hud. A FakeHudModel stands in for the
## replicated-state adapter per SPEC-ui-hud testing.

const HUD_SCENE := "res://scenes/ui/hud.tscn"

var _hud: Hud


func before_each() -> void:
	_hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	_hud.hud_model = _FakeHudModel.new()
	add_child_autofree(_hud)


func test_hud_instantiates_with_every_widget() -> void:
	assert_not_null(_hud.get_node("Root") as Control)
	assert_not_null(_hud.get_node("Root/LanternOrb") as LanternOrb)
	assert_not_null(_hud.get_node("Root/Teammates") as HBoxContainer)
	assert_not_null(_hud.get_node("Root/FloorSign") as FloorSign)
	assert_not_null(_hud.get_node("Root/LampMap") as LampMap)
	assert_not_null(_hud.get_node("Root/Currencies") as CurrencyReadout)
	assert_not_null(_hud.get_node("Root/StatusRow") as StatusRow)
	assert_not_null(_hud.get_node("Root/Weapons") as HBoxContainer)
	assert_not_null(_hud.get_node("Root/AbilityRow") as AbilityRow)
	assert_not_null(_hud.get_node("Root/RelicRope") as RelicRope)


func test_modal_screens_start_hidden() -> void:
	assert_false(_hud.choice_popup.visible)
	assert_false(_hud.rope_vote_prompt.visible)
	assert_false(_hud.pause_layer.visible)


func test_orb_reflects_the_model() -> void:
	assert_eq(_hud.lantern_orb.hp_ratio, 0.5)
	assert_eq(_hud.lantern_orb.hp_current, 50)
	assert_eq(_hud.lantern_orb.hp_max, 100)


func test_teammate_badges_are_built_from_the_model() -> void:
	var badges := _hud.teammate_badges.get_children()
	assert_eq(badges.size(), 1, "one teammate in the fake model")
	var badge := badges[0] as TeammateBadge
	assert_eq(badge.display_name, "Player2")
	assert_eq(badge.hp_ratio, 0.75)
	assert_false(badge.is_downed)


func test_weapon_diamonds_show_two_placeholders() -> void:
	assert_eq(_hud.weapons_box.get_child_count(), 2)
	var slot := _hud.weapons_box.get_child(0) as WeaponDiamond
	assert_eq(slot.slot_number, "1")
	assert_eq(slot.display_name, "-")
	assert_not_null(_hud.weapons_box.get_child(1) as WeaponDiamond)


func test_floor_sign_is_placeheld_until_floor_state_arrives() -> void:
	assert_eq(_hud.floor_sign.floor_text, "FLOOR -")


func test_currencies_relics_and_statuses_come_from_the_model() -> void:
	assert_eq(_hud.currencies.gold, 1240)
	assert_eq(_hud.currencies.ore, 18)
	assert_eq(_hud.currencies.echo, 6)
	assert_eq(_hud.relic_rope.relics.size(), 1)
	assert_eq(_hud.status_row.statuses.size(), 1)


func test_model_refresh_updates_the_widgets() -> void:
	var fake: _FakeHudModel = _hud.hud_model
	fake.override_local_ratio = 0.25
	fake.refresh(0)
	assert_eq(_hud.lantern_orb.hp_ratio, 0.25)


func test_the_pause_overlay_toggles_without_pausing_the_tree() -> void:
	_hud.set_paused_view(true)
	assert_true(_hud.pause_layer.visible)
	assert_false(get_tree().paused, "co-op: the host keeps simulating")
	_hud.set_paused_view(false)
	assert_false(_hud.pause_layer.visible)


# Fake model ---------------------------------------------------------------
# SPEC-ui-hud testing: every UI scene instantiates with a fake HudModel. This
# one drives the HUD with fixed state; production HudModel (unit-tested
# separately) refreshes from replicated player state.

class _FakeHudModel:
	extends HudModel

	var override_local_ratio: float = 0.5

	func refresh(_local_peer_id: int) -> void:
		local_hp_ratio = override_local_ratio
		local_hp_current = 50
		local_hp_max = 100
		local_is_downed = false
		gold = 1240
		ore_total = 18
		echo_shards = 6
		teammates.clear()
		var t := HudTeammate.new()
		t.peer_id = 2
		t.display_name = "Player2"
		t.slot = 1
		t.hp_ratio = 0.75
		t.is_downed = false
		teammates.append(t)
		relics.clear()
		var relic := HudRelic.new()
		relic.id = &"ember_boots"
		relic.display_name = "Ember Boots"
		relics.append(relic)
		statuses.clear()
		var status := HudStatus.new()
		status.status = StatusEffects.Status.BURN
		status.stacks = 2
		statuses.append(status)
		changed.emit()
