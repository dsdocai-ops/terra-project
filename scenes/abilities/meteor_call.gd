class_name MeteorCallCast
extends AbilityCast
## Meteor Call (SPEC-abilities section 8, Fire): a meteor lands on the cursor after
## IMPACT_DELAY seconds. The landing is one hit in the radius, then a burning
## ground (a Zone) stays for the rest of the cast's life. Owned by abilities.
## Sync: host only. A client's copy shows nothing, since the landing is only
## scheduled on the host.

const IMPACT_DELAY: float = 0.6
const IMPACT_SECONDS: float = 0.1
const GROUND_TICK_SECONDS: float = 0.5
## The burning ground hits softer than the landing, at this share of the damage.
const GROUND_DAMAGE_FACTOR: float = 0.25
const RADIUS: float = 56.0

## Seconds of TimeManager-scaled time until the meteor lands. Zero once it has
## landed, or when the cast never scheduled one (a client's copy).
var _landing_in: float = 0.0


func _perform() -> void:
	_landing_in = IMPACT_DELAY


func advance(delta: float) -> void:
	if _landing_in > 0.0:
		_landing_in -= delta * TimeManager.scale_for(_timed_node())
		if _landing_in <= 0.0:
			_land()
	super.advance(delta)


## The landing hit at the cursor, and the burning ground that outlasts it.
func _land() -> void:
	var radius: float = RADIUS * size_mult()
	spawn_zone(aim_point, radius, IMPACT_SECONDS, IMPACT_SECONDS, build_hit())
	spawn_zone(aim_point, radius, life_seconds - IMPACT_DELAY, GROUND_TICK_SECONDS, scaled_hit(GROUND_DAMAGE_FACTOR))
