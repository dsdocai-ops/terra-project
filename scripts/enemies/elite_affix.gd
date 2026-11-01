class_name EliteAffix
extends RefCounted
## Enum for elite affix types. NONE is a plain (non-affixed) elite and the
## default for every non-elite. Owned by enemies-ai (W4-A1). Each affix's
## behaviour is one small EliteBehavior script, looked up by `behavior_script`.

enum Affix { NONE, SHIELDED, HASTED, SPLITTING, VAMPIRIC, EXPLOSIVE, TELEPORTING }

const BEHAVIOR_PATHS: Dictionary = {
	Affix.SHIELDED: "res://scripts/enemies/affix_shielded.gd",
	Affix.HASTED: "res://scripts/enemies/affix_hasted.gd",
	Affix.SPLITTING: "res://scripts/enemies/affix_splitting.gd",
	Affix.VAMPIRIC: "res://scripts/enemies/affix_vampiric.gd",
	Affix.EXPLOSIVE: "res://scripts/enemies/affix_explosive.gd",
	Affix.TELEPORTING: "res://scripts/enemies/affix_teleporting.gd",
}


## The behaviour script for `affix`, or null for NONE and any unknown value.
static func behavior_script(affix: Affix) -> Script:
	if not BEHAVIOR_PATHS.has(affix):
		return null
	return load(BEHAVIOR_PATHS[affix]) as Script
