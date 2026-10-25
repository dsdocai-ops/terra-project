class_name BuildingPurchase
extends RefCounted
## Buying a town building level with ore (SPEC-town "Buildings", W5-B4). Owned by
## town. Host-only in a session: purchases spend the host's profile. Pure over the
## profile it is handed, so a test drives it without the save file; `saver` is
## called once on a sale (default `SaveManager.save`).

const REFUSAL_NONE: StringName = &""
const REFUSAL_NO_BUILDING: StringName = &"no_building"
const REFUSAL_MAX_LEVEL: StringName = &"max_level"
const REFUSAL_NOT_ENOUGH_ORE: StringName = &"not_enough_ore"
const DATA_DIR: String = "res://data/town/"


static func building_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for file: String in DirAccess.get_files_at(DATA_DIR):
		# Exported builds list remapped resources as "<name>.tres.remap".
		var resource_file: String = file.trim_suffix(".remap")
		if resource_file.ends_with(".tres"):
			ids.append(StringName(resource_file.get_basename()))
	ids.sort()
	return ids


static func data_for(building_id: StringName) -> BuildingData:
	var path: String = DATA_DIR + String(building_id) + ".tres"
	if building_id == &"" or not ResourceLoader.exists(path):
		return null
	return load(path) as BuildingData


## The cost of the next level, or null at the cap / for an unknown building.
static func next_cost(profile: PlayerProfile, building_id: StringName) -> BuildingLevel:
	var data: BuildingData = data_for(building_id)
	if data == null:
		return null
	var level: int = profile.building_level(building_id)
	if level >= BuildingData.MAX_LEVEL or level >= data.levels.size():
		return null
	return data.levels[level]


static func refusal_for(profile: PlayerProfile, building_id: StringName) -> StringName:
	if data_for(building_id) == null:
		return REFUSAL_NO_BUILDING
	var cost: BuildingLevel = next_cost(profile, building_id)
	if cost == null:
		return REFUSAL_MAX_LEVEL
	if profile.ore_count(cost.ore_id) < cost.ore_amount:
		return REFUSAL_NOT_ENOUGH_ORE
	return REFUSAL_NONE


## Spends the ore and raises the building one level. Returns REFUSAL_NONE on a
## sale, else the reason; a refusal changes nothing and saves nothing.
static func purchase(profile: PlayerProfile, building_id: StringName, saver: Callable = Callable()) -> StringName:
	var reason: StringName = refusal_for(profile, building_id)
	if reason != REFUSAL_NONE:
		return reason
	var cost: BuildingLevel = next_cost(profile, building_id)
	profile.ore[String(cost.ore_id)] = profile.ore_count(cost.ore_id) - cost.ore_amount
	profile.town[String(building_id)] = profile.building_level(building_id) + 1
	if saver.is_valid():
		saver.call()
	else:
		SaveManager.save()
	return REFUSAL_NONE
