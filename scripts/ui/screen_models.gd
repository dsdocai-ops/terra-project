class_name ScreenModels
extends RefCounted
## The rows behind the week 5 screens (SPEC-ui-hud): pure functions from run and
## profile state to ScreenPanel sections, so every number on a screen is a tested
## value rather than something read off a node. Owned by ui-hud (Dev B).
## Sync: none. Callers hand in replicated state (RunResult, RunPlayerState,
## PlayerProfile); nothing here reads the scene tree.

const DASH: String = "-"

const PAUSE_RESUME: int = 0
const PAUSE_SETTINGS: int = 1
const PAUSE_CODEX: int = 2
const PAUSE_QUIT_TO_TOWN: int = 3
const PAUSE_LEAVE_COOP: int = 4

const STAT_NAMES: Array[String] = [
	"Max HP", "Attack", "Defense", "Move speed", "Attack speed", "Dodge cooldown",
	"Crit chance", "Crit damage", "Ability power", "Cooldown reduction", "Luck",
]


## "lantern_staff" -> "Lantern Staff".
static func pretty(id: StringName) -> String:
	var words: PackedStringArray = String(id).split("_", false)
	var out: PackedStringArray = PackedStringArray()
	for word: String in words:
		out.append(word.capitalize())
	return " ".join(out)


# --- pause -------------------------------------------------------------------


## The pause list. "Leave Co-op" only exists in a co-op session; "Quit to Town"
## only in a run, and asks to be pressed twice because it counts as a death.
static func pause_items(in_run: bool, co_op: bool, confirming_quit: bool) -> Array[String]:
	var items: Array[String] = ["Resume", "Settings", "Codex"]
	if in_run:
		items.append("Press again: counts as a death" if confirming_quit else "Quit to Town")
	if co_op:
		items.append("Leave Co-op")
	return items


## What a pause choice means, by its label rather than its position, since the
## list changes with the session.
static func pause_action(items: Array[String], index: int) -> StringName:
	if index < 0 or index >= items.size():
		return &""
	var label: String = items[index]
	if label == "Resume":
		return &"resume"
	if label == "Settings":
		return &"settings"
	if label == "Codex":
		return &"codex"
	if label == "Quit to Town" or label.begins_with("Press again"):
		return &"quit_to_town"
	if label == "Leave Co-op":
		return &"leave_coop"
	return &""


# --- death / extract screen ---------------------------------------------------


static func death_title(reason: RunEndReason.Reason) -> String:
	match reason:
		RunEndReason.Reason.EXTRACT:
			return "YOU CLIMBED OUT"
		RunEndReason.Reason.VICTORY:
			return "THE PIT IS QUIET"
		RunEndReason.Reason.ABORT:
			return "YOU LEFT THE PIT"
	return "YOU FELL"


static func ore_total(table: Dictionary) -> int:
	var raw: Variant = table.get(&"ore", 0)
	if raw is Dictionary:
		var total: int = 0
		for amount: Variant in (raw as Dictionary).values():
			total += int(amount)
		return total
	return int(raw)


static func relic_count(table: Dictionary) -> int:
	var raw: Variant = table.get(&"relics", [])
	return (raw as Array).size() if raw is Array else 0


## The kept-versus-lost table and the run's own numbers for one player.
static func death_sections(result: RunResult, peer_id: int) -> Array[ScreenPanel.Section]:
	var kept: Dictionary = result.kept.get(peer_id, RunResult.empty_table())
	var lost: Dictionary = result.lost.get(peer_id, RunResult.empty_table())
	var green: Color = UiPalette.ALLY_GREEN
	var red: Color = UiPalette.HP_RED
	var table: ScreenPanel.Section = ScreenPanel.Section.new("What you keep")
	table.add(PackedStringArray(["", "Kept", "Lost"]), PackedColorArray([UiPalette.ROPE, UiPalette.ROPE, UiPalette.ROPE]))
	var rows: Array = [
		["Gold", int(kept.get(&"gold", 0)), int(lost.get(&"gold", 0))],
		["Ore", ore_total(kept), ore_total(lost)],
		["Relics", relic_count(kept), relic_count(lost)],
	]
	for row: Array in rows:
		table.add(
			PackedStringArray([row[0], str(row[1]), str(row[2])]),
			PackedColorArray([UiPalette.PARCHMENT, green, red if int(row[2]) > 0 else UiPalette.DOWNED_GREY]),
		)
	for earned: Array in [["Echo Shards", &"echo_shards"], ["Class XP", &"class_xp"]]:
		table.add(
			PackedStringArray([earned[0], str(int(kept.get(earned[1], 0))), DASH]),
			PackedColorArray([UiPalette.PARCHMENT, green, UiPalette.DOWNED_GREY]),
		)
	var stats: ScreenPanel.Section = ScreenPanel.Section.new("The dive")
	stats.pair("Floors cleared", str(result.floors_cleared))
	stats.pair("Seed", str(result.seed), UiPalette.DOWNED_GREY)
	return [table, stats]


# --- inventory ----------------------------------------------------------------


## Relics held, grouped with a stack count, in the order they were taken.
static func relic_stacks(relics: Array[StringName]) -> Array[Array]:
	var counts: Dictionary[StringName, int] = {}
	var order: Array[StringName] = []
	for id: StringName in relics:
		if not counts.has(id):
			order.append(id)
		counts[id] = int(counts.get(id, 0)) + 1
	var stacks: Array[Array] = []
	for id: StringName in order:
		stacks.append([id, counts[id]])
	return stacks


## `stat_values` is Stat index -> value, empty when the player carries no
## StatBlock yet; every stat still gets a row.
static func inventory_sections(
	slice: RunPlayerState,
	run: RunState,
	stat_values: Dictionary[int, float],
) -> Array[ScreenPanel.Section]:
	var relics: ScreenPanel.Section = ScreenPanel.Section.new("Relics")
	var stacks: Array[Array] = relic_stacks(slice.relics) if slice != null else ([] as Array[Array])
	if stacks.is_empty():
		relics.pair("None yet", "")
	for stack: Array in stacks:
		var data: RelicData = RelicFlow.data_for(stack[0])
		var name: String = data.display_name if data != null and data.display_name != "" else pretty(stack[0])
		var tint: Color = UiPalette.rarity_color(data.rarity) if data != null else UiPalette.PARCHMENT
		relics.add(
			PackedStringArray([name, "x%d" % int(stack[1]) if int(stack[1]) > 1 else ""]),
			PackedColorArray([tint, UiPalette.ROPE]),
		)
	var stats: ScreenPanel.Section = ScreenPanel.Section.new("Stats")
	for index: int in STAT_NAMES.size():
		stats.pair(STAT_NAMES[index], format_stat(stat_values[index]) if stat_values.has(index) else DASH)
	var loadout: ScreenPanel.Section = ScreenPanel.Section.new("Loadout")
	if slice != null:
		loadout.pair("Class", pretty(slice.class_id))
		for weapon_id: StringName in slice.weapon_ids:
			var mutations: int = slice.mutations_for(weapon_id).size()
			loadout.pair(pretty(weapon_id), "+%d mutations" % mutations if mutations > 0 else "")
		loadout.pair("Ascension", pretty(slice.ascension) if slice.ascension != &"" else "none")
		loadout.pair("Potions", str(slice.potions.size()))
	if run != null:
		loadout.pair("Floor", "%d / %d" % [run.floor_index, RunState.MAX_FLOOR])
	return [relics, stats, loadout]


static func format_stat(value: float) -> String:
	if absf(value - roundf(value)) < 0.005:
		return str(int(roundf(value)))
	return "%.2f" % value


# --- town ---------------------------------------------------------------------


## The Blacksmith's weapons, cheapest first (ties by name). A menu choice maps
## back to a weapon through this order.
static func blacksmith_order() -> Array[StringName]:
	var stock: Array[StringName] = Blacksmith.stock()
	stock.sort_custom(func(a: StringName, b: StringName) -> bool:
		if Blacksmith.PRICES[a] != Blacksmith.PRICES[b]:
			return int(Blacksmith.PRICES[a]) < int(Blacksmith.PRICES[b])
		return String(a) < String(b))
	return stock


static func blacksmith_subtitle(profile: PlayerProfile) -> String:
	return "Gold %d" % profile.gold_banked


## One carved line per weapon with its price: "Sledgehammer  150", or in
## brackets when it cannot be bought now (owned, or too dear), then Close.
static func blacksmith_buttons(ids: Array[StringName], profile: PlayerProfile) -> Array[String]:
	var labels: Array[String] = []
	for weapon_id: StringName in ids:
		var name: String = pretty(weapon_id)
		var price: int = int(Blacksmith.PRICES[weapon_id])
		if profile.weapons_unlocked.has(String(weapon_id)):
			labels.append("(%s  owned)" % name)
		elif Blacksmith.refusal_for(profile, weapon_id) == Blacksmith.REFUSAL_NONE:
			labels.append("%s  %d" % [name, price])
		else:
			labels.append("(%s  %d)" % [name, price])
	labels.append("Close")
	return labels


## The build prompt for an unbuilt (or upgradable) building.
static func build_sections(profile: PlayerProfile, building_id: StringName) -> Array[ScreenPanel.Section]:
	var data: BuildingData = BuildingPurchase.data_for(building_id)
	var section: ScreenPanel.Section = ScreenPanel.Section.new()
	if data == null:
		section.pair("Unknown building", "")
		return [section]
	var cost: BuildingLevel = BuildingPurchase.next_cost(profile, building_id)
	if cost == null:
		section.pair("Fully upgraded", "level %d" % profile.building_level(building_id))
		return [section]
	var have: int = profile.ore_count(cost.ore_id)
	section.pair("Level %d" % (profile.building_level(building_id) + 1), "", UiPalette.GOLD)
	section.pair(cost.description, "")
	var enough: bool = have >= cost.ore_amount
	section.pair("Cost", "%d %s" % [cost.ore_amount, pretty(cost.ore_id)])
	section.pair("You have", str(have), UiPalette.ALLY_GREEN if enough else UiPalette.HP_RED)
	if not enough:
		section.pair("Needs %d more" % (cost.ore_amount - have), "", UiPalette.HP_RED)
	return [section]


static func build_title(building_id: StringName) -> String:
	var data: BuildingData = BuildingPurchase.data_for(building_id)
	return data.display_name if data != null else pretty(building_id)


## The pre-run screen: this player's loadout and the party's ready state.
static func setup_sections(setup: RunSetup, local_peer: int, peers: Array[int]) -> Array[ScreenPanel.Section]:
	var mine: SelectionState = setup.selections.get(local_peer)
	var loadout: ScreenPanel.Section = ScreenPanel.Section.new("Your loadout")
	if mine != null:
		loadout.pair("Character", pretty(mine.character_id))
		loadout.pair("Class", pretty(mine.class_id))
		loadout.pair("Weapons", " + ".join(PackedStringArray([pretty(mine.weapon_ids[0]), pretty(mine.weapon_ids[1])])))
	loadout.pair("Start floor", str(setup.start_floor))
	if MapRoom.ascension_picked_at_start(setup.start_floor):
		loadout.pair("Ascension", "picked on arrival", UiPalette.ROPE)
	var party: ScreenPanel.Section = ScreenPanel.Section.new("Party")
	for peer_id: int in peers:
		var selection: SelectionState = setup.selections.get(peer_id)
		var ready_text: String = "ready" if selection != null and selection.ready else ("choosing" if selection != null else "waiting")
		var tint: Color = UiPalette.ALLY_GREEN if ready_text == "ready" else UiPalette.DOWNED_GREY
		party.add(PackedStringArray(["Player %d" % peer_id, ready_text]), PackedColorArray([UiPalette.PARCHMENT, tint]))
	return [loadout, party]
