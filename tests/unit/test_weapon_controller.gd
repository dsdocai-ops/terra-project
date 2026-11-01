extends GutTest
## Tests for the affinity hooks on WeaponController (SPEC-weapons "Class affinity
## hooks", W5-G8): `affinity_active_changed` fires when the active slot's weapon
## changes or its affinity list changes, and a hit from an affinity weapon carries
## the "affinity" tag. The class effects that attach on the signal are W5-G10.
## Owned by weapons. Local only: the signal and the tag are client-side readouts
## and change no game state. Uses the real player scene; the controller is driven
## by hand and no timers run.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const LANTERN_STAFF := "res://data/weapons/lantern_staff.tres"
const CROSSBOW := "res://data/weapons/crossbow.tres"
const PICKAXE := "res://data/weapons/pickaxe.tres"

var _player: Player
var _weapons: WeaponController
var _announcements: Array[bool] = []


func before_each() -> void:
	var world := Node2D.new()
	add_child_autofree(world)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	world.add_child(_player)
	_weapons = _player.get_node("WeaponController") as WeaponController
	_announcements.clear()
	_weapons.affinity_active_changed.connect(_on_affinity_changed)


func after_each() -> void:
	if _weapons.affinity_active_changed.is_connected(_on_affinity_changed):
		_weapons.affinity_active_changed.disconnect(_on_affinity_changed)


func _on_affinity_changed(active: bool) -> void:
	_announcements.append(active)


func _staff() -> WeaponData:
	return load(LANTERN_STAFF) as WeaponData


func _mage_affinity() -> Array[StringName]:
	var ids: Array[StringName] = [&"lantern_staff"]
	return ids


# --- the signal on equip and unequip --------------------------------------------------------

func test_equipping_an_affinity_weapon_into_the_active_slot_announces_true() -> void:
	_weapons.set_affinity_ids(_mage_affinity())
	_announcements.clear()
	_weapons.equip(_weapons.active_slot, _staff())
	assert_eq(_announcements, [true], "the active slot now holds an affinity weapon")


func test_equipping_a_non_affinity_weapon_into_the_active_slot_announces_false() -> void:
	_weapons.set_affinity_ids(_mage_affinity())
	_weapons.equip(_weapons.active_slot, _staff())
	_announcements.clear()
	_weapons.equip(_weapons.active_slot, load(CROSSBOW) as WeaponData)
	assert_eq(_announcements, [false], "the crossbow is not on the list")


func test_unequipping_the_active_slot_announces_false() -> void:
	_weapons.set_affinity_ids(_mage_affinity())
	_weapons.equip(_weapons.active_slot, _staff())
	_announcements.clear()
	_weapons.equip(_weapons.active_slot, null)
	assert_eq(_announcements, [false], "an empty slot is not an affinity weapon")


func test_equipping_into_the_inactive_slot_announces_nothing() -> void:
	_weapons.set_affinity_ids(_mage_affinity())
	_announcements.clear()
	var other: int = (_weapons.active_slot + 1) % WeaponController.SLOT_COUNT
	_weapons.equip(other, _staff())
	assert_eq(_announcements, [], "the live weapon did not change")


func test_swapping_to_an_affinity_weapon_announces_true() -> void:
	_weapons.set_affinity_ids(_mage_affinity())
	var other: int = (_weapons.active_slot + 1) % WeaponController.SLOT_COUNT
	_weapons.equip(other, _staff())
	_announcements.clear()
	assert_true(_weapons.swap(), "the swap lockout is clear in a fresh controller")
	assert_eq(_announcements, [true], "the live weapon is now the affinity staff")


func test_set_affinity_ids_keeps_its_own_copy_of_the_list() -> void:
	var ids: Array[StringName] = [&"lantern_staff"]
	_weapons.set_affinity_ids(ids)
	ids.clear()
	_announcements.clear()
	_weapons.equip(_weapons.active_slot, _staff())
	assert_eq(_announcements, [true], "clearing the caller's array does not drop the affinity")


func test_set_affinity_ids_announces_the_active_weapon_state() -> void:
	_weapons.equip(_weapons.active_slot, _staff())
	_announcements.clear()
	_weapons.set_affinity_ids(_mage_affinity())
	assert_eq(_announcements, [true], "the class sets its list after the weapon is live")


# --- the affinity tag on hits -----------------------------------------------------------------

func test_a_hit_from_an_affinity_weapon_carries_the_affinity_tag() -> void:
	_weapons.set_affinity_ids(_mage_affinity())
	_weapons.equip(_weapons.active_slot, _staff())
	var spec: AttackSpec = _staff().light_combo[0]
	var hit: HitInfo = _weapons.build_hit(spec, Vector2.RIGHT, 0.0, false)
	assert_true(hit.tags.has(&"affinity"), "the staff is on the affinity list")


func test_a_hit_from_a_non_affinity_weapon_has_no_affinity_tag() -> void:
	_weapons.set_affinity_ids(_mage_affinity())
	_weapons.equip(_weapons.active_slot, load(PICKAXE) as WeaponData)
	var spec: AttackSpec = (load(PICKAXE) as WeaponData).light_combo[0]
	var hit: HitInfo = _weapons.build_hit(spec, Vector2.RIGHT, 0.0, false)
	assert_false(hit.tags.has(&"affinity"), "the pickaxe is not on the list")
