class_name Blacksmith
extends RefCounted
## The Blacksmith's level 1 service: buy weapons with banked gold (SPEC-town,
## W5-B4). Owned by town. Weapon prices live here until the weapons module's
## WeaponData carries one (blocked on Dev A, W7); class-granted weapons (Twin
## Daggers, Hand Cannon, Grave Scythe, Longsword) and the secret Leviathan's Tooth
## are never sold. The level 2/3 damage tiers and the rare stock are week 6+.

const REFUSAL_NONE: StringName = &""
const REFUSAL_NOT_BUILT: StringName = &"not_built"
const REFUSAL_NOT_FOR_SALE: StringName = &"not_for_sale"
const REFUSAL_OWNED: StringName = &"owned"
const REFUSAL_POOR: StringName = &"not_enough_gold"

const PRICES: Dictionary[StringName, int] = {
	&"sledgehammer": 150,
	&"shortbow": 150,
	&"throwing_knives": 150,
	&"spore_tome": 150,
	&"chain_whip": 200,
	&"greataxe": 250,
	&"rust_anchor": 250,
	&"tide_orb": 250,
	&"blood_grimoire": 250,
	&"drill_gauntlets": 300,
	&"saw_boomerang": 300,
	&"reaper_chain": 300,
}


static func stock() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(PRICES.keys())
	return ids


static func refusal_for(profile: PlayerProfile, weapon_id: StringName) -> StringName:
	if profile.building_level(&"blacksmith") < 1:
		return REFUSAL_NOT_BUILT
	if not PRICES.has(weapon_id):
		return REFUSAL_NOT_FOR_SALE
	if profile.weapons_unlocked.has(String(weapon_id)):
		return REFUSAL_OWNED
	if profile.gold_banked < int(PRICES[weapon_id]):
		return REFUSAL_POOR
	return REFUSAL_NONE


static func buy_weapon(profile: PlayerProfile, weapon_id: StringName, saver: Callable = Callable()) -> StringName:
	var reason: StringName = refusal_for(profile, weapon_id)
	if reason != REFUSAL_NONE:
		return reason
	profile.gold_banked -= int(PRICES[weapon_id])
	profile.weapons_unlocked.append(String(weapon_id))
	if saver.is_valid():
		saver.call()
	else:
		SaveManager.save()
	return REFUSAL_NONE
