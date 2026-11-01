class_name ThunderStepCast
extends AbilityCast
## Thunder Step (SPEC-abilities section 8, Storm): the player teleports toward the
## cursor, up to the extra number of pixels, and lightning strikes where they land.
## A wall at the cursor stops the step at the last free point before it (D-P9).
## Owned by abilities. Sync: host only, the player's position is set on the host.

const STRIKE_RADIUS: float = 48.0
const STRIKE_SECONDS: float = 0.1
## How far apart the wall samples are along the step, in pixels. A tile is 64
## pixels wide, so a step at this spacing cannot skip over a wall tile.
const WALL_SAMPLE_PIXELS: float = 4.0


func _perform() -> void:
	var start: Vector2 = origin()
	var reach: float = minf((aim_point - start).length(), extra())
	var landing: Vector2 = landing_before_wall(start, start + aim_dir * reach, _walls())
	if player != null:
		player.global_position = landing
	spawn_zone(landing, STRIKE_RADIUS * size_mult(), STRIKE_SECONDS, STRIKE_SECONDS, build_hit())


## The last point of the step from `start` to `end` before a wall tile on `walls`,
## sampled every WALL_SAMPLE_PIXELS. `end` when no wall is on the way or there is
## no `walls` layer. Points are global, as the player's position is. Static so the
## rule can be tested on a bare layer.
static func landing_before_wall(start: Vector2, end: Vector2, walls: TileMapLayer) -> Vector2:
	if walls == null:
		return end
	var steps: int = ceili(start.distance_to(end) / WALL_SAMPLE_PIXELS)
	var landing: Vector2 = start
	for i: int in range(1, steps + 1):
		var point: Vector2 = start.lerp(end, float(i) / steps)
		if walls.get_cell_source_id(walls.local_to_map(walls.to_local(point))) != -1:
			break
		landing = point
	return landing


## The world's wall layer, or null with no world (a test with no floor).
func _walls() -> TileMapLayer:
	return GameState.world.walls_layer if GameState.world != null else null
