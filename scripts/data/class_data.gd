class_name ClassData
extends ContentData
## A player class (SPEC-classes-characters "ClassData"): role, the weapons that
## give its affinity, its passive and affinity effects, its Shift skill and its
## Ascensions. Owned by classes-characters. Sync: none (data). The host reads it
## when a player picks a class; ClassController attaches the effects.
##
## `unlock_flag` empty means the class is open at start. `class_resource_kind`
## names the class resource ("scrap", "souls", or empty); it is not `resource_name`
## because Resource already owns that property. `class_tree` (ClassTreeNodeData)
## and pair bonuses (ClassPairData) are not built this week (D-P5, BRIEF Out of
## scope), so this resource has no `class_tree` field yet.

@export var role: String = ""
## Weapon ids (`WeaponData.id`) that grant this class's affinity while equipped.
@export var affinity_weapon_ids: Array[StringName] = []
## Effect attached while an affinity weapon is equipped.
@export var affinity_effect: GDScript
## Effect attached for the whole run.
@export var passive_effect: GDScript
## The Shift skill node, with its own cooldown.
@export var class_skill: PackedScene
## Unlocked at mastery 5 and chosen in the select screen.
@export var class_skill_alt: PackedScene
## Exactly two Tier 1 Ascensions, once content lands (Week 7).
@export var ascensions: Array[AscensionData] = []
## Effect that listens to `ultimate_used` for this class.
@export var ultimate_twist: GDScript
## Stat -> base value. Read once at spawn; changes go through StatBlock modifiers.
@export var base_stats: Dictionary[StatBlock.Stat, float] = {}
## Flag that unlocks the class. Empty means open at start.
@export var unlock_flag: StringName = &""
## Weapon id granted free with the class.
@export var free_weapon_id: StringName = &""
## "scrap", "souls", or empty for a class with no class resource.
@export var class_resource_kind: StringName = &""
