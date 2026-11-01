class_name ToxicCloudCast
extends AbilityCast
## Toxic Cloud (SPEC-abilities section 8, Poison; SINKHOLE_SPEC "throw a gas
## canister that leaves a growing Toxin cloud"): one Zone lands on the cursor and
## grows from START_SHARE of its full size to all of it over the cast's life. Each
## tick is a POISON hit, so the element's TOXIN status comes through build_hit.
## Owned by abilities. Sync: host only. A client's copy shows the cast, and the
## host's zone moves the cloud's radius.

const RADIUS: float = 56.0
const TICK_SECONDS: float = 0.5
## The cloud's radius at the start, as a share of its full size.
const START_SHARE: float = 0.4

var _cloud: Zone = null
var _full_radius: float = 0.0
## Seconds of TimeManager-scaled life the cloud has run, for its growth.
var _grown: float = 0.0


func _perform() -> void:
	_full_radius = RADIUS * size_mult()
	_cloud = spawn_zone(aim_point, _full_radius * START_SHARE, life_seconds, TICK_SECONDS, build_hit())


func advance(delta: float) -> void:
	_grown += delta * TimeManager.scale_for(_timed_node())
	if _cloud != null and is_instance_valid(_cloud) and life_seconds > 0.0:
		var share: float = clampf(_grown / life_seconds, 0.0, 1.0)
		_cloud.set_radius(_full_radius * lerpf(START_SHARE, 1.0, share))
	super.advance(delta)
