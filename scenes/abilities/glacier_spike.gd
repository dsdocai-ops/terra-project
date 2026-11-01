class_name GlacierSpikeCast
extends AbilityCast
## Glacier Spike (SPEC-abilities section 8, Frost): a line of ice spikes erupts
## from the player along the aim. The extra number is the spike count, one spike
## every SPIKE_SPACING pixels. Each spike is a one-tick Zone. Owned by abilities.
## Sync: host only.

const SPIKE_SPACING: float = 36.0
const SPIKE_RADIUS: float = 20.0
const SPIKE_SECONDS: float = 0.1


func _perform() -> void:
	var start: Vector2 = origin()
	var radius: float = SPIKE_RADIUS * size_mult()
	for index: int in int(extra()):
		var at: Vector2 = start + aim_dir * SPIKE_SPACING * float(index + 1)
		spawn_zone(at, radius, SPIKE_SECONDS, SPIKE_SECONDS, build_hit())
