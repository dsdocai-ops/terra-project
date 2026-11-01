class_name ShadowClonesCast
extends AbilityCast
## Shadow Clones (SPEC-abilities section 8, Shadow): CLONE_COUNT FriendlyUnits
## appear around the caster for the rank's duration. They follow the caster, and
## every melee swing the caster starts is copied onto each clone, which hits at the
## caster's damage in a circle of the swing's reach (not its arc). The count is the
## spec's three at every rank, so the rank's `extra` is unused. Owned by abilities.
## Sync: host only for the hits. The host spawns the clones, runs their follow and
## their hits, and sends each clone's position to the client (FriendlyUnit). A
## client's copy spawns the same three clones at the same points, visual only, and
## moves to the positions the host sends.

const CLONE_COUNT: int = 3
const SPAWN_RADIUS: float = 48.0
## Node name prefix for the clones, so a client's copy of each clone has the same
## node path as the host's (the position RPC resolves by path).
const CLONE_NAME: String = "Clone"

## The clones this cast spawned on this peer. They free with the cast.
var units: Array[FriendlyUnit] = []


func _ready() -> void:
	super._ready()
	if not multiplayer.is_server():
		_spawn_units()


## Host: spawns the clones and copies the caster's melee swings onto them.
func _perform() -> void:
	_spawn_units()
	if player == null:
		return
	var weapons := player.get_node_or_null("WeaponController") as WeaponController
	if weapons != null:
		weapons.swing_begun.connect(copy_swing)


## Copies one of the caster's swings onto every live clone. A projectile is not
## copied, since a clone swings rather than fires. Only connected on the host, so
## the hits stay host-only.
func copy_swing(spec: AttackSpec, hit: HitInfo) -> void:
	if spec == null or hit == null or spec.shape == AttackSpec.Shape.PROJECTILE:
		return
	for unit: FriendlyUnit in units:
		if is_instance_valid(unit) and not unit.is_queued_for_deletion():
			unit.strike_with(hit, spec.reach, spec.active_seconds)


## Spawns the clones in a ring of SPAWN_RADIUS around the origin, each living as
## long as the cast does.
func _spawn_units() -> void:
	var centre: Vector2 = origin()
	for index: int in CLONE_COUNT:
		var unit := FriendlyUnit.new()
		unit.name = "%s%d" % [CLONE_NAME, index]
		unit.setup(player, life_seconds)
		add_child(unit)
		var angle: float = TAU * float(index) / float(CLONE_COUNT)
		unit.global_position = centre + Vector2.RIGHT.rotated(angle) * SPAWN_RADIUS
		units.append(unit)
