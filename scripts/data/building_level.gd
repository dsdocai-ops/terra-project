class_name BuildingLevel
extends Resource
## One upgrade step of a town building: the ore it costs and what it unlocks.
## Owned by town (W5-B4). Sync: none (data). SPEC-town "Buildings": level N
## consumes the ore the table lists in order; amounts are tuned in week 12.

@export var ore_id: StringName = &""
@export var ore_amount: int = 0
@export_multiline var description: String = ""
