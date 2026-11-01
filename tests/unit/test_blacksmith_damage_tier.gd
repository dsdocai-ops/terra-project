extends GutTest
## Blacksmith weapon damage tier (SPEC-weapons "Weapon damage tiers from
## Blacksmith add percent to weapon base_damage"; SPEC-town "weapon damage tier
## +10%"). The tier reaches the player as a `StatBlock` ATTACK modifier on the
## active weapon, never a base edit, and `Damage.compute` reads that stat, so a
## higher tier gives a higher damage number. Owned by weapons (W4-A5). Sync: the
## modifier is applied on the host where the hit is computed; no RPC.

const PLAYER_SCENE_PATH: String = "res://scenes/player/player.tscn"
const CROSSBOW_PATH: String = "res://data/weapons/crossbow.tres"
const PICKAXE_PATH: String = "res://data/weapons/pickaxe.tres"
const TIER_SOURCE: StringName = &"blacksmith_tier"
const SEED: int = 4242

var _player: Player = null
var _weapons: WeaponController = null
var _stats: StatBlock = null


func before_each() -> void:
	_player = (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as Player
	add_child_autofree(_player)
	_player.position = Vector2.ZERO
	_weapons = _player.get_node("WeaponController") as WeaponController
	_stats = _player.get_node("StatBlock") as StatBlock


func after_each() -> void:
	_stats = null
	_weapons = null
	_player = null


func _attack() -> float:
	return _stats.get_value(StatBlock.Stat.ATTACK)


func _damage_for(attacker: StatBlock) -> int:
	var hit := HitInfo.new()
	hit.base_damage = 20.0
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var target := StatBlock.new()
	add_child_autofree(target)
	return Damage.compute(attacker, target, hit, rng)


# --- the modifier ------------------------------------------------------------------

func test_a_tier_adds_percent_attack_through_a_modifier() -> void:
	var before: float = _attack()
	_weapons.equip(0, load(CROSSBOW_PATH) as WeaponData, 2)
	assert_almost_eq(_attack(), before * 1.2, 0.001, "tier 2 is +20 % of ATTACK")


func test_the_base_attack_is_never_edited_by_a_tier() -> void:
	var base_before: float = float(_stats.base.get(StatBlock.Stat.ATTACK, 0.0))
	_weapons.equip(0, load(CROSSBOW_PATH) as WeaponData, 3)
	assert_eq(float(_stats.base.get(StatBlock.Stat.ATTACK, 0.0)), base_before, "base ATTACK unchanged")


func test_tier_zero_adds_no_modifier() -> void:
	var before: float = _attack()
	_weapons.equip(0, load(CROSSBOW_PATH) as WeaponData, 0)
	assert_eq(_attack(), before, "no tier, no change to ATTACK")


func test_only_the_active_weapons_tier_applies() -> void:
	var before: float = _attack()
	_weapons.equip(0, load(CROSSBOW_PATH) as WeaponData, 2)
	_weapons.equip(1, load(PICKAXE_PATH) as WeaponData, 3)
	assert_almost_eq(_attack(), before * 1.2, 0.001, "slot 0 is active, so its tier 2 is the one applied")


func test_swapping_to_a_tierless_weapon_drops_the_previous_tier() -> void:
	var before: float = _attack()
	_weapons.equip(0, load(CROSSBOW_PATH) as WeaponData, 2)
	_weapons.equip(1, load(PICKAXE_PATH) as WeaponData, 0)
	assert_true(_weapons.swap(), "the swap goes through")
	assert_eq(_attack(), before, "slot 1 has no tier, so the tier from slot 0 is gone")


# --- Damage.compute reads ATTACK ---------------------------------------------------

func test_a_higher_tier_produces_a_higher_damage_number() -> void:
	_weapons.equip(0, load(CROSSBOW_PATH) as WeaponData, 0)
	var base_damage: int = _damage_for(_stats)
	_weapons.equip(0, load(CROSSBOW_PATH) as WeaponData, 3)
	var tiered_damage: int = _damage_for(_stats)
	assert_gt(tiered_damage, base_damage, "tier 3 out-damages tier 0 with the same roll")


func test_the_damage_number_scales_with_the_attack_stat() -> void:
	# Pins the read: with no tier and no crit, the number is the ATTACK ratio on
	# the base damage (a crit-free roll) times the mitigation term, so it moves
	# with ATTACK and nothing else changes.
	var before: int = _damage_for(_stats)
	_stats.add_modifier(StatBlock.Stat.ATTACK, 0.0, 1.0, TIER_SOURCE)
	var doubled: int = _damage_for(_stats)
	assert_gt(doubled, before, "doubling ATTACK raises the damage number")


# --- the production caller: the profile's tier reaches the live loadout ------------

func _spawn_with_profile_tier(peer: int, tier: int) -> StatBlock:
	var had_profile: PlayerProfile = SaveManager.profile
	var profile: PlayerProfile = PlayerProfile.defaults()
	profile.weapon_damage_tiers = {"pickaxe": tier}
	SaveManager.profile = profile
	var player := (load(PLAYER_SCENE_PATH) as PackedScene).instantiate() as Player
	player.peer_id = peer
	add_child_autofree(player)
	SaveManager.profile = had_profile
	return player.get_node("StatBlock") as StatBlock


func test_the_local_profile_tier_for_the_starting_weapon_reaches_attack_on_spawn() -> void:
	# The spawned player reads the tier the local profile holds for its starting
	# weapon (pickaxe.tres is id `pickaxe`), so a bought tier is live in play.
	var stats := _spawn_with_profile_tier(multiplayer.get_unique_id(), 2)
	var base_attack: float = float(stats.base.get(StatBlock.Stat.ATTACK, 0.0))
	assert_almost_eq(stats.get_value(StatBlock.Stat.ATTACK), base_attack * 1.2, 0.001, "pickaxe tier 2 is +20 % of ATTACK from the first frame")


func test_a_remote_players_spawn_never_takes_this_machines_profile_tier() -> void:
	# On the host, a client's player is built with the host's profile on the host's
	# disk. Its tier must not be the host's, so its ATTACK stays at the base.
	var stats := _spawn_with_profile_tier(multiplayer.get_unique_id() + 1, 2)
	var base_attack: float = float(stats.base.get(StatBlock.Stat.ATTACK, 0.0))
	assert_eq(stats.get_value(StatBlock.Stat.ATTACK), base_attack, "a remote player takes no tier from this profile")
