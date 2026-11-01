class_name AscensionData
extends ContentData
## One of a class's two Tier 1 Ascensions, and the Tier 2 form it evolves into
## (SPEC-classes-characters "AscensionData"). Owned by classes-characters.
## Sync: none (data). Resource only: no entries are authored in Week 5 (BRIEF,
## Out of scope).

## The class this Ascension belongs to (`ClassData.id`).
@export var class_id: StringName = &""
## Effect attached at Tier 1.
@export var tier1_effect: GDScript
## Effect attached in addition at Tier 2.
@export var tier2_effect: GDScript
@export var tier2_name: String = ""
@export var description_t1: String = ""
@export var description_t2: String = ""
## Optional: the class skill this Ascension swaps for another one.
@export var replaces_class_skill: PackedScene
