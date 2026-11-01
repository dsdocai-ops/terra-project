class_name AbilityRank
extends Resource
## One rank (1 to 3) of an ability: the numbers that a rank changes. Owned by
## abilities. Sync: none (data). The host reads it when a cast spawns.
##
## `damage_mult` scales the ability's base_damage, `size_mult` scales its area or
## length, and `duration` is in seconds of TimeManager-scaled time (0 when the
## cast has none). `extra` is the ability's own number, such as Chain Lightning's
## jump count; the cast script that reads it says what it means.

@export var damage_mult: float = 1.0
@export var size_mult: float = 1.0
@export var duration: float = 0.0
@export var extra: float = 0.0
