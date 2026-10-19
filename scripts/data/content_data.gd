class_name ContentData
extends Resource
## Base for every content Resource (weapons, relics, abilities, enemies, ...).
## Owned by foundation; `tags`, `effect_script`, `vfx_id`, `sfx_id` are used by
## effect-system and art-audio. Sync: none (data).
##
## `id` must equal the .tres file name (snake_case); the data-driven tests
## enforce it. `display_name` is what the player sees.

@export var id: StringName = &""
@export var display_name: String = ""
## 1 to 2 tags from the Tags vocabulary (SPEC-effect-system) for synergies.
@export var tags: Array[StringName] = []
## Script extending Effect that implements this item's behaviour, if any.
@export var effect_script: GDScript
@export var icon: Texture2D
## Keys into the VFX library and SfxBank (SPEC-art-audio).
@export var vfx_id: StringName = &""
@export var sfx_id: StringName = &""
