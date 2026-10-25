class_name BuildingData
extends ContentData
## One of Hollowmere's 11 buildings (SPEC-town "Buildings"). Owned by town
## (W5-B4). Sync: none (data). `data/town/<id>.tres`, id = file name.
## Level 0 is "not built" (a sign); `levels[0]` is the cost and unlock of level 1.

@export var levels: Array[BuildingLevel] = []
@export var npc_id: StringName = &""
## Week 5 ships three buildings working (Blacksmith, Shrine of Echoes, Tavern);
## the other eight show their level-0 sign until their week.
@export var functional_in_v1: bool = false

const MAX_LEVEL: int = 3
