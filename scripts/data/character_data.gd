class_name CharacterData
extends ContentData
## A playable character (SPEC-classes-characters "CharacterData"): a passive, an
## ultimate, an unlock flag, art and three story events. Owned by
## classes-characters. Sync: none (data). The host reads it at run start.
##
## `unlock_flag` empty means the character is unlocked by default (Wren).

## Effect attached for the whole run.
@export var passive_effect: GDScript
## The ultimate this character spends the meter on.
@export var ultimate: AbilityData
@export var unlock_flag: StringName = &""
@export var portrait: Texture2D
@export var sprite_frames: SpriteFrames
## Three dialogue ids (`story-dialogue`).
@export var story_events: Array[StringName] = []
