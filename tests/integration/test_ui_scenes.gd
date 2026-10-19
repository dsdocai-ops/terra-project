extends GutTest
## Integration: the HUD scene instantiates over the world flow and renders the
## typed HudModel state (W2-B5). Owned by ui-hud. A FakeHudModel stands in for
## the replicated-state adapter per SPEC-ui-hud testing.

const HUD_SCENE := "res://scenes/ui/hud.tscn"

var _hud: Hud


func before_each() -> void:
	_hud = (load(HUD_SCENE) as PackedScene).instantiate() as Hud
	_hud.hud_model = _FakeHudModel.new()
	add_child_autofree(_hud)


func test_hud_instantiates_with_its_panels() -> void:
	var root := _hud.get_node("Root") as Control
	assert_not_null(root)
	assert_eq(root.get_parent(), _hud)
	assert_not_null(_hud.get_node("Root/TopLeft/OwnHpBar") as HpBar)
	assert_not_null(_hud.get_node("Root/TopCenter/FloorLabel") as Label)
	assert_not_null(_hud.get_node("Root/WeaponSlots") as HBoxContainer)


func test_own_hp_bar_reflects_the_model() -> void:
	var own_bar := _hud.get_node("Root/TopLeft/OwnHpBar") as HpBar
	assert_eq(own_bar.ratio, 0.5)


func test_teammate_bars_are_built_from_the_model() -> void:
	var bars := _hud.get_node("Root/TopLeft/TeammateBars") as VBoxContainer
	var rows := bars.get_children()
	assert_eq(rows.size(), 1, "one teammate in the fake model")
	var row := rows[0] as HBoxContainer
	assert_eq((row.get_node("Name") as Label).text, "Player2")
	assert_eq((row.get_node("Bar") as HpBar).ratio, 0.75)


func test_weapon_slots_show_two_placeholders() -> void:
	var box := _hud.get_node("Root/WeaponSlots") as HBoxContainer
	assert_eq(box.get_child_count(), 2)
	var slot := box.get_child(0) as WeaponSlot
	assert_eq(slot.slot_number, "1")
	assert_eq(slot.display_name, "-")
	assert_not_null(box.get_child(1) as WeaponSlot)


func test_floor_label_is_placeheld_until_floor_state_arrives() -> void:
	var label := _hud.get_node("Root/TopCenter/FloorLabel") as Label
	assert_eq(label.text, "FLOOR -")


func test_model_refresh_updates_the_widgets() -> void:
	var fake: _FakeHudModel = _hud.hud_model
	assert_eq((_hud.get_node("Root/TopLeft/OwnHpBar") as HpBar).ratio, 0.5)
	fake.override_local_ratio = 0.25
	fake.refresh(0)
	assert_eq((_hud.get_node("Root/TopLeft/OwnHpBar") as HpBar).ratio, 0.25)
	assert_eq((_hud.get_node("Root/TopCenter/FloorLabel") as Label).text, "FLOOR -")


# Fake model ---------------------------------------------------------------
# SPEC-ui-hud testing: every UI scene instantiates with a fake HudModel. This
# one drives the HUD with fixed state; production HudModel (unit-tested
# separately) refreshes from replicated player state.

class _FakeHudModel:
	extends HudModel

	var override_local_ratio: float = 0.5

	func refresh(_local_peer_id: int) -> void:
		local_hp_ratio = override_local_ratio
		local_is_downed = false
		teammates.clear()
		var t := HudTeammate.new()
		t.peer_id = 2
		t.display_name = "Player2"
		t.slot = 1
		t.hp_ratio = 0.75
		t.is_downed = false
		teammates.append(t)
		changed.emit()