class_name ChoiceOption
extends RefCounted
## One card on the ChoicePopup: what the player reads before choosing. Built from
## a RelicData today; the ability swap and Ascension popups (weeks 5 and 7) build
## the same shape from their own data. Owned by ui-hud (Dev B). Sync: none.

var id: StringName = &""
var title: String = ""
var description: String = ""
## A RelicData.Rarity value; drives the tablet's colour and the carved icon shape.
var rarity: int = RelicData.Rarity.COMMON

## The pixel-art icon, drawn inside the card's carved circle; null falls back to a rarity-shaped gem.
var icon: Texture2D = null
## The synergy tags shown under the description.
var tags: Array[StringName] = []
## Why this card cannot be taken (already at max stacks, for instance); empty when it can.
var disabled_reason: String = ""


static func from_relic(data: RelicData) -> ChoiceOption:
	var option := ChoiceOption.new()
	if data == null:
		return option
	option.id = data.id
	option.title = data.display_name if data.display_name != "" else String(data.id).capitalize()
	option.description = data.description
	option.rarity = data.rarity
	option.icon = data.icon
	option.tags = data.tags.duplicate()
	return option


## Options for the ids a Shrine offered, in offer order. An id with no data is
## skipped so one broken .tres cannot blank the whole popup.
static func from_relic_ids(ids: Array[StringName]) -> Array[ChoiceOption]:
	var options: Array[ChoiceOption] = []
	for id: StringName in ids:
		var data: RelicData = RelicFlow.data_for(id)
		if data != null:
			options.append(from_relic(data))
	return options
