class_name LanternStaffAttack
extends WeaponAttack
## The Lantern Staff's per-weapon attack node (SPEC-weapons Magic row, D-P6): its
## charged heavy is a beam along the aim, and every enemy inside the beam's light
## cone gets the `lit` flag and the light bonus (a damage-taken factor through the
## enemy's Hurtbox, the same path the staggered state uses) for LIT_SECONDS. The cone
## is geometric: its half angle is the heavy's `arc_degrees` / 2 from
## `lantern_staff.tres`, the same wedge the heavy's hitbox uses (G8b), so what is lit
## is what is hit. Its reach is the heavy's reach at the charge the beam fires with
## (`cone_range_for`, G8c), and the scene's PointLight2D draws the same cone at that
## reach. The damage scale by charge is the
## controller's (`build_hit`), not this node's. Owned by
## weapons. Sync: the hook runs inside the swing each peer executes; `lit` is set and
## cleared only on the host (`lit_targets` takes `is_host`) and rides the enemy's
## StateSync to client copies (W5-G8d); the timer and the bonus stay host state, so a
## client copy changes nothing. The cone light is local
## presentation on every peer.

## The weapon data the cone's angle is read from.
const STAFF_DATA: String = "res://data/weapons/lantern_staff.tres"
## The heavy's reach at zero charge, in px (its `reach` in lantern_staff.tres). A beam
## at another charge reaches `cone_range_for(charge)`; this is the default range.
const ZERO_CHARGE_RANGE: float = 150.0
## The damage-taken factor a lit enemy carries while its light lasts. The spec gives
## no number (SPEC-weapons "light bonus"); chosen here per D-P8.
const LIT_DAMAGE_FACTOR: float = 1.15
## The Hurtbox source the light bonus is filed under, so it stacks with others.
const LIT_SOURCE: StringName = &"lit"
## How long a lit enemy keeps the light after the beam, in TimeManager-scaled seconds.
const LIT_SECONDS: float = 4.0
## How long the cone light stays drawn after a heavy, in seconds (presentation only).
const BEAM_SECONDS: float = 0.4
## Child node in `lantern_staff.tscn`: the PointLight2D that draws the cone.
const CONE_NODE: String = "LightCone"

## Host-side: lit enemy -> seconds of light left. Freed enemies are dropped on the
## next tick.
var _lit_left: Dictionary = {}
var _beam_left: float = 0.0
var _cone: PointLight2D = null
## The cone's half angle in degrees, read once from the staff's heavy wedge.
var _half_angle_degrees: float = cone_half_angle_degrees()
## The cone texture's radius in px: the full-charge reach, rounded up. One texture
## serves every charge; `heavy` scales the light to the reach it fires with.
var _texture_radius: float = ceilf(cone_range_for(1.0))


func _ready() -> void:
	_cone = get_node_or_null(CONE_NODE) as PointLight2D
	if _cone == null:
		return
	_cone.texture = _cone_texture()
	_cone.enabled = false


## Half of the heavy's wedge in degrees either side of the aim: the staff's heavy
## `arc_degrees` divided by 2 (G8b). The lit cone and the heavy hitbox both use it.
static func cone_half_angle_degrees() -> float:
	return heavy_spec().arc_degrees * 0.5


## The staff's heavy attack, the spec the cone's angle and reach are read from.
static func heavy_spec() -> AttackSpec:
	var staff: WeaponData = load(STAFF_DATA) as WeaponData
	return staff.heavy


## The cone's reach in px at `charge`: the heavy's reach at that charge, the same
## number the heavy's hitbox uses (`WeaponController.melee_reach`), so what is lit is
## what the heavy reaches (G8c).
static func cone_range_for(charge: float) -> float:
	return WeaponController.melee_reach(heavy_spec(), charge, true)


## The charged beam went live: the cone is drawn at the reach for `charge` and every
## enemy in it is lit (the lighting is host only).
func heavy(charge: float) -> void:
	if player == null or not player.is_inside_tree():
		return
	var range_px: float = cone_range_for(charge)
	_beam_left = BEAM_SECONDS
	if _cone != null:
		_cone.rotation = aim_dir.angle()
		_cone.texture_scale = range_px / _texture_radius
		_cone.enabled = true
	var candidates: Array[Node2D] = []
	for node: Node in player.get_tree().get_nodes_in_group(Enemy.GROUP):
		# A member that is not a 2D node casts to null, and lit_targets skips it.
		candidates.append(node as Node2D)
	for target: Node2D in lit_targets(player.global_position, aim_dir, candidates, multiplayer.is_server(), _half_angle_degrees, range_px):
		_light(target as Enemy)

## Runs on every peer. A client never lights anything (`lit_targets` is empty there),
## so its `_lit_left` stays empty and this loop does nothing on it.
func _physics_process(delta: float) -> void:
	_beam_left = maxf(_beam_left - delta, 0.0)
	if _beam_left <= 0.0 and _cone != null:
		_cone.enabled = false
	var scaled: float = delta * (TimeManager.scale_for(player) if player != null else 1.0)
	for key: Variant in _lit_left.keys():
		if not is_instance_valid(key):
			_lit_left.erase(key)
			continue
		var left: float = float(_lit_left[key]) - scaled
		if left > 0.0:
			_lit_left[key] = left
		else:
			_unlight(key as Enemy)


## Lights `target` for LIT_SECONDS and files the light bonus on its Hurtbox. A
## refresh while lit restarts the timer.
func _light(target: Enemy) -> void:
	target.lit = true
	target.hurtbox.set_damage_taken_factor(LIT_SOURCE, LIT_DAMAGE_FACTOR)
	_lit_left[target] = LIT_SECONDS


func _unlight(target: Enemy) -> void:
	_lit_left.erase(target)
	target.lit = false
	target.hurtbox.clear_damage_taken_factor(LIT_SOURCE)


## The cone as a light texture: apex at the centre, the cone along +x, alpha falling
## from 1 at the apex to 0 at the range. The cone's own test (`in_cone`) decides the
## shape, so the drawn cone and the lit enemies come from one rule. The colour is
## grey at the alpha, so the light reads it the same whether it uses the alpha or
## the luminance. The texture spans `_texture_radius`, the full-charge reach.
func _cone_texture() -> Texture2D:
	var side: int = int(_texture_radius) * 2
	var centre := Vector2(_texture_radius, _texture_radius)
	var image := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	for y: int in side:
		for x: int in side:
			var offset := Vector2(x + 0.5, y + 0.5) - centre
			var alpha: float = 0.0
			if in_cone(Vector2.ZERO, Vector2.RIGHT, offset, _half_angle_degrees, _texture_radius):
				alpha = clampf(1.0 - offset.length() / _texture_radius, 0.0, 1.0)
			image.set_pixel(x, y, Color(alpha, alpha, alpha, alpha))
	return ImageTexture.create_from_image(image)


## Whether `point` lies inside the cone from `origin` along `aim`. The apex counts
## as inside; a zero aim lights nothing but the apex (a zero aim normalizes to zero,
## whose dot product is 0, below any cone's cosine).
static func in_cone(origin: Vector2, aim: Vector2, point: Vector2,
		half_angle_degrees: float, range_px: float = ZERO_CHARGE_RANGE) -> bool:
	var offset: Vector2 = point - origin
	var distance: float = offset.length()
	if distance > range_px:
		return false
	if distance == 0.0:
		return true
	return offset.normalized().dot(aim.normalized()) >= cos(deg_to_rad(half_angle_degrees))


## The enemies among `candidates` that the beam lights. Empty on a client (the
## host alone sets `lit`); non-enemy nodes are skipped. `range_px` is the beam's reach.
static func lit_targets(origin: Vector2, aim: Vector2, candidates: Array[Node2D], is_host: bool,
		half_angle_degrees: float, range_px: float = ZERO_CHARGE_RANGE) -> Array[Node2D]:
	var lit: Array[Node2D] = []
	if not is_host:
		return lit
	for candidate: Node2D in candidates:
		if candidate is Enemy and in_cone(origin, aim, candidate.global_position, half_angle_degrees, range_px):
			lit.append(candidate)
	return lit
