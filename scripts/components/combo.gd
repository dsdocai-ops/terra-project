class_name Combo
extends RefCounted
## An element combo: the payload `Events.combo_triggered` carries. Owned by
## stats-status.
##
## SPEC-stats-status, "Element combos": "When a status is applied to a target
## that already has another element's status, the combo fires once, consumes the
## listed stacks, and emits `Events.combo_triggered`." The six rows of that
## table are `Kind`, and `NAMES` is the word the debug overlay, the HUD and a
## log line use:
##
##   SHATTER           Fire on Frost, or Frost on Fire   burst 200 % of the
##                                                       trigger damage in 64 px,
##                                                       consumes Chill/Freeze
##   CONDUCT           Storm on a `wet` target           the shock spreads to the
##                                                       connected water area
##   BLIGHT_EXPLOSION  Fire on Toxin                     explosion 40 % per Toxin
##                                                       stack, consumes Toxin
##   HEMORRHAGE        Shadow (Mark) on Bleed            Bleed ticks crit for 4 s
##   SUPERCONDUCT      Frost on Storm, or Storm on Frost -30 % Defense for 8 s
##   COLLAPSE          Void on any other status          pull enemies within
##                                                       128 px to the target
##
## It is a class with an enum rather than a bare enum because SPEC-effect-system
## fixes the bus parameter as `combo: Combo`, so the payload has to be an
## instance; `Kind` is the enum the spec means when stats-status's "Interfaces
## provided" lists "`Combo` enum and `Scaling`". Only `StatusEffects` builds one
## — the combo table lives there, next to the statuses whose elements it keys
## off — and it is the only thing that emits it.
##
## Sync: none. An ephemeral value object, built and spent on the host. Clients
## render a combo from replicated state (the HUD and the VFX), never by
## computing one: SPEC-effect-system, "an effect script never runs on a client".
## SPEC-stats-status's last line about the combo table — "Reactive skill node
## (+40%) and Elementalist synergy (x2) multiply combo damage" — is applied to
## `damage` by `StatusEffects.scaled_combo_damage()` before the payload is
## emitted, so the number a listener reads here already carries both hooks
## (G25).

enum Kind {
	SHATTER,
	CONDUCT,
	BLIGHT_EXPLOSION,
	HEMORRHAGE,
	SUPERCONDUCT,
	COLLAPSE,
}

## Combo -> the name a log line or a debug row prints. The spec's own row names,
## lower-cased, matching `StatusEffects.STATUS_NAMES`' shape.
const NAMES: Dictionary[int, StringName] = {
	Kind.SHATTER: &"shatter",
	Kind.CONDUCT: &"conduct",
	Kind.BLIGHT_EXPLOSION: &"blight_explosion",
	Kind.HEMORRHAGE: &"hemorrhage",
	Kind.SUPERCONDUCT: &"superconduct",
	Kind.COLLAPSE: &"collapse",
}

## Which combo this is.
var kind: Kind = Kind.SHATTER
## The combo's own damage, for the rows that deal some: SHATTER's burst,
## BLIGHT_EXPLOSION's explosion and CONDUCT's spread. 0 for the rows that land a
## flag, a modifier or a request instead.
var damage: int = 0
## The scaled seconds the combo's lasting effect runs for, for the two rows
## whose Effect column names a duration (HEMORRHAGE 4 s, SUPERCONDUCT 8 s). 0 for
## the rest.
var duration: float = 0.0
## The radius the combo reached, for the two rows whose Effect column names one
## (SHATTER 64 px, COLLAPSE 128 px). 0 for the rest.
var radius: float = 0.0
## How many stacks the combo consumed off the target, for the two rows that
## consume (SHATTER's Chill/Freeze, BLIGHT_EXPLOSION's Toxin). 0 for the rest.
var stacks: int = 0


func _init(combo_kind: Kind = Kind.SHATTER) -> void:
	kind = combo_kind


## The name this combo is known by, or an empty name for an unknown id.
func name() -> StringName:
	return NAMES.get(kind, &"")
