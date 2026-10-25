class_name ProjectileSpec
extends RefCounted
## What `Effect.fire_projectile()` hands the projectile spawner: the scene to
## instantiate and the numbers it should fly with. Owned by effect-system
## (W4-B2); the spec's field list is
## `ProjectileSpec (RefCounted: scene, speed, damage, element, pierce, bounce)`.
##
## It is a value object, not a node: the effect builds it on the host, the
## spawner reads it, and nothing keeps it alive afterwards. `to_dict()` /
## `from_dict()` are the plain-type form the spawner path uses — every value is
## a String, float or int, with the scene travelling as its resource path and
## the element as its enum value, matching the `EnemySpawnInfo` /
## `ProjectileSpawnInfo` convention.
##
## Sync: host-only. Built on the host by an effect and forwarded to the
## projectile spawner, which replicates the spawned projectile to every peer.

const KEY_SCENE_PATH: String = "scene_path"
const KEY_SPEED: String = "speed"
const KEY_DAMAGE: String = "damage"
const KEY_ELEMENT: String = "element"
const KEY_PIERCE: String = "pierce"
const KEY_BOUNCE: String = "bounce"

## The scene the spawner instantiates. Null is legal: a spec with no scene
## still carries the numbers, which is what the "spawner absent" path reports.
var scene: PackedScene = null
## Pixels per second along the firing direction.
var speed: float = 0.0
## Base damage before `Damage.compute` scaling.
var damage: float = 0.0
## Drives status application and VFX colour (`HitInfo.Element`).
var element: HitInfo.Element = HitInfo.Element.NONE
## How many targets the projectile passes through before it stops.
var pierce: int = 0
## How many times it ricochets off a wall or target.
var bounce: int = 0


func _init(
	p_scene: PackedScene = null,
	p_speed: float = 0.0,
	p_damage: float = 0.0,
	p_element: HitInfo.Element = HitInfo.Element.NONE,
	p_pierce: int = 0,
	p_bounce: int = 0,
) -> void:
	scene = p_scene
	speed = p_speed
	damage = p_damage
	element = p_element
	pierce = p_pierce
	bounce = p_bounce


## Plain-type form for the spawner. The scene becomes its resource path, the
## element its enum value; both are rebuilt by `from_dict()`.
func to_dict() -> Dictionary:
	var scene_path: String = ""
	if scene != null:
		scene_path = scene.resource_path
	return {
		KEY_SCENE_PATH: scene_path,
		KEY_SPEED: speed,
		KEY_DAMAGE: damage,
		KEY_ELEMENT: int(element),
		KEY_PIERCE: pierce,
		KEY_BOUNCE: bounce,
	}


## Rebuilds a spec from `to_dict()`'s output. A missing, absent or non-scene
## path leaves `scene` null rather than erroring, so a spec that only carries
## numbers (or arrives from an older payload) is still usable; an element value
## outside the enum degrades to `NONE` for the same reason.
static func from_dict(data: Dictionary) -> ProjectileSpec:
	var spec: ProjectileSpec = ProjectileSpec.new()
	var scene_path: String = str(data.get(KEY_SCENE_PATH, ""))
	if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
		var loaded: Resource = load(scene_path)
		if loaded is PackedScene:
			spec.scene = loaded
	spec.speed = float(data.get(KEY_SPEED, 0.0))
	spec.damage = float(data.get(KEY_DAMAGE, 0.0))
	spec.element = _element_from(data.get(KEY_ELEMENT, int(HitInfo.Element.NONE)))
	spec.pierce = int(data.get(KEY_PIERCE, 0))
	spec.bounce = int(data.get(KEY_BOUNCE, 0))
	return spec


## Written as a `match` rather than an int cast so an out-of-range value can
## never become a valid element by accident (and so the conversion raises no
## int-to-enum warning).
static func _element_from(raw: Variant) -> HitInfo.Element:
	match int(raw):
		HitInfo.Element.FIRE:
			return HitInfo.Element.FIRE
		HitInfo.Element.FROST:
			return HitInfo.Element.FROST
		HitInfo.Element.STORM:
			return HitInfo.Element.STORM
		HitInfo.Element.SHADOW:
			return HitInfo.Element.SHADOW
		HitInfo.Element.POISON:
			return HitInfo.Element.POISON
		HitInfo.Element.EARTH:
			return HitInfo.Element.EARTH
		HitInfo.Element.BLOOD:
			return HitInfo.Element.BLOOD
		HitInfo.Element.VOID:
			return HitInfo.Element.VOID
		_:
			return HitInfo.Element.NONE
