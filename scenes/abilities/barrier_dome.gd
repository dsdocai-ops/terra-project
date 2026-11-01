class_name BarrierDomeCast
extends AbilityCast
## Barrier Dome (SPEC-abilities section 8, Utility; SINKHOLE_SPEC "a dome that
## blocks all enemy projectiles for 4 seconds (allies can stand inside)"). One Zone
## stands on the cursor for the rank's duration with blocks_projectiles set, so it
## ends every enemy Projectile inside its edge. It deals no damage and holds nothing
## back from allies: allied bolts pass, and allied units inside take hits as usual.
## Owned by abilities. Sync: host only; the blocking runs on the host, and a
## client's copy only shows the dome.

const RADIUS: float = 64.0


func _perform() -> void:
	var dome: Zone = spawn_zone(aim_point, RADIUS * size_mult(), life_seconds, life_seconds, null)
	dome.blocks_projectiles = true
