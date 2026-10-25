class_name WeaponController
extends Node
## Holds a player's two weapon slots and turns an `AttackSpec` into a live hit:
## a melee hitbox in front of the player or a projectile (SPEC-weapons
## `WeaponController`). Owned by weapons. Sync: host-authoritative. Hitboxes and
## projectile spawns run on the host only (`Hurtbox.receive` and the spawner
## both refuse clients); a client runs the same calls so its movement and
## timing predict the host's, and nothing it spawns can deal damage.

signal weapon_changed(slot: int, weapon: WeaponData)

const SLOT_COUNT: int = 2
const SWAP_LOCKOUT_SECONDS: float = 0.2
## Light combo resets to step 0 after this long without an attack.
const COMBO_RESET_SECONDS: float = 0.6
## Full charge adds this much to a heavy's damage multiplier.
const HEAVY_CHARGE_BONUS: float = 0.8
## A full charge adds this much poise damage to a heavy (scaled by the charge).
const HEAVY_POISE_CHARGE_BONUS: float = 30.0
## A perfect release (within 0.15 s after full charge) adds this share to the
## heavy's damage and poise damage.
const PERFECT_RELEASE_BONUS: float = 0.2
const ARC_SEGMENTS: int = 6
const DEFAULT_WEAPON_PATHS: Array[String] = [
	"res://data/weapons/pickaxe.tres",
	"res://data/weapons/crossbow.tres",
]
const PROJECTILE_ID: StringName = &"bolt"

var slots: Array[WeaponData] = []
var active_slot: int = 0
var combo_step: int = 0

var _combo_timer: float = 0.0
## Seconds left on each slot's weapon skill, counted in TimeManager-scaled time.
var _skill_cooldowns: Array[float] = [0.0, 0.0]
var _swap_lockout: float = 0.0
var _hitbox: Hitbox = null
var _hitbox_shape: CollisionShape2D = null
var _slash_arc: SlashArc = null
var _player: Player = null


func _ready() -> void:
	_player = get_parent() as Player
	slots.resize(SLOT_COUNT)
	for index: int in SLOT_COUNT:
		slots[index] = load(DEFAULT_WEAPON_PATHS[index]) as WeaponData
	_build_hitbox()
	_build_slash_arc()


func _physics_process(delta: float) -> void:
	_swap_lockout = maxf(_swap_lockout - delta, 0.0)
	var scaled: float = delta * (TimeManager.scale_for(_player) if _player != null else 1.0)
	for slot: int in SLOT_COUNT:
		_skill_cooldowns[slot] = maxf(_skill_cooldowns[slot] - scaled, 0.0)
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			combo_step = 0


func _build_hitbox() -> void:
	_hitbox = Hitbox.new()
	_hitbox.name = "MeleeHitbox"
	_hitbox.team = Team.Kind.PLAYER
	_hitbox_shape = CollisionShape2D.new()
	_hitbox.add_child(_hitbox_shape)
	var pivot: Node2D = _player.get_node_or_null("WeaponPivot") as Node2D if _player != null else null
	if pivot != null:
		pivot.add_child(_hitbox)
	else:
		add_child(_hitbox)


## The swing visual sits where the hitbox does, so its wedge is the real hitbox.
func _build_slash_arc() -> void:
	_slash_arc = SlashArc.new()
	_slash_arc.name = "SlashArc"
	var pivot: Node2D = _player.get_node_or_null("WeaponPivot") as Node2D if _player != null else null
	if pivot != null:
		pivot.add_child(_slash_arc)
	else:
		add_child(_slash_arc)


func equip(slot: int, data: WeaponData) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	slots[slot] = data
	combo_step = 0
	weapon_changed.emit(slot, data)


func active_weapon() -> WeaponData:
	return slots[active_slot]


func can_swap() -> bool:
	return _swap_lockout <= 0.0


## Swaps to the other slot unless the 0.2 s lockout is running. Returns whether
## it swapped.
func swap() -> bool:
	if not can_swap():
		return false
	active_slot = (active_slot + 1) % SLOT_COUNT
	_swap_lockout = SWAP_LOCKOUT_SECONDS
	combo_step = 0
	weapon_changed.emit(active_slot, slots[active_slot])
	if _player != null and multiplayer.is_server():
		Events.weapon_swapped.emit(_player, active_slot)
	return true


## The next light attack spec; advances the combo. The reset timer does not run
## while an attack is playing: the Attack state starts it when the attack ends
## (`attack_finished`).
func take_light() -> AttackSpec:
	var weapon: WeaponData = active_weapon()
	if weapon == null or weapon.light_combo.is_empty():
		return null
	var spec: AttackSpec = weapon.light_combo[combo_step % weapon.light_combo.size()]
	combo_step = weapon.next_step(combo_step)
	_combo_timer = 0.0
	return spec


## True when the active weapon has a skill that is off cooldown.
func skill_ready() -> bool:
	var weapon: WeaponData = active_weapon()
	return weapon != null and weapon.skill != null and _skill_cooldowns[active_slot] <= 0.0


func skill_cooldown_left(slot: int = -1) -> float:
	return _skill_cooldowns[active_slot if slot < 0 else slot]


## Fires the active weapon's skill: returns its AttackSpec and starts the
## cooldown (`skill_cooldown_seconds`, TimeManager-scaled), or null when there is
## no skill or it is still cooling down. The caller runs the returned spec as an
## attack; the perfect-dodge check lives in AttackController.
func weapon_skill() -> AttackSpec:
	if not skill_ready():
		return null
	var weapon: WeaponData = active_weapon()
	_skill_cooldowns[active_slot] = weapon.skill_cooldown_seconds
	return weapon.skill


func take_heavy() -> AttackSpec:
	var weapon: WeaponData = active_weapon()
	return weapon.heavy if weapon != null else null


## An attack began: the combo reset timer stops until it ends.
func attack_started() -> void:
	_combo_timer = 0.0


## An attack ended (its recovery ran out, or it was cancelled): the 0.6 s combo
## reset timer starts now, not when the button was pressed.
func attack_finished() -> void:
	_combo_timer = COMBO_RESET_SECONDS


## Share of full move speed while charging a heavy.
func charge_move_factor() -> float:
	var weapon: WeaponData = active_weapon()
	return weapon.charge_move_factor if weapon != null else 0.3


func heavy_charge_seconds() -> float:
	var weapon: WeaponData = active_weapon()
	return weapon.heavy_charge_seconds if weapon != null else 0.8


## The hit payload for one swing or shot. `charge` is 0..1 and only scales
## heavies.
func build_hit(spec: AttackSpec, dir: Vector2, charge: float, heavy: bool, perfect: bool = false) -> HitInfo:
	var hit := HitInfo.new()
	hit.source = _player
	hit.owner_player = _player
	var scale: float = 1.0 + (charge * HEAVY_CHARGE_BONUS if heavy else 0.0)
	var perfect_scale: float = 1.0 + (PERFECT_RELEASE_BONUS if heavy and perfect else 0.0)
	hit.base_damage = spec.base_damage * scale * perfect_scale
	hit.element = spec.element
	hit.is_heavy = heavy
	hit.poise_damage = (spec.poise_damage + (HEAVY_POISE_CHARGE_BONUS * charge if heavy else 0.0)) * perfect_scale
	hit.knockback = dir * spec.knockback
	hit.hit_stun_seconds = spec.hit_stun_seconds
	hit.is_projectile = spec.shape == AttackSpec.Shape.PROJECTILE
	var weapon: WeaponData = active_weapon()
	if weapon != null:
		hit.tags.append(weapon.id)
	hit.tags.append(&"ranged" if hit.is_projectile else &"melee")
	if heavy and perfect:
		hit.tags.append(&"perfect_release")
	if weapon != null and weapon.skill != null and weapon.skill == spec:
		hit.tags.append(&"weapon_skill")
	if not heavy and weapon != null and weapon.light_combo.size() > 1 and weapon.light_combo.back() == spec:
		hit.tags.append(CombatFeedback.FINISHER_TAG)
	return hit


## Goes live: a melee hitbox is turned on for the attack's active window, a
## projectile is spawned once. The caller (the Attack state) calls `end_swing`
## when the window closes.
func begin_swing(spec: AttackSpec, dir: Vector2, charge: float, heavy: bool, perfect: bool = false) -> void:
	var hit: HitInfo = build_hit(spec, dir, charge, heavy, perfect)
	if spec.shape == AttackSpec.Shape.PROJECTILE:
		_fire_projectile(spec, dir, hit)
		return
	_hitbox_shape.shape = _melee_shape(spec, charge, heavy)
	_hitbox.rotation = dir.angle() if spec.shape == AttackSpec.Shape.ARC else 0.0
	_hitbox.template = hit
	_hitbox.hit_once_per_target = true
	_hitbox.active = multiplayer.is_server()
	_show_swing(spec, dir, charge, heavy)


func end_swing() -> void:
	if _hitbox != null:
		_hitbox.active = false
	if _slash_arc != null:
		_slash_arc.stop()


## Forward reach of a melee swing in px, including the heavy's charge bonus.
static func melee_reach(spec: AttackSpec, charge: float, heavy: bool) -> float:
	return spec.reach * (1.0 + (charge * 0.35 if heavy else 0.0))


## Plays the swing visual here, and on the host also on every other peer except
## the owner (who predicted it and already plays it). Real seconds of the active
## window, so a slow attack speed stretches it like the Attack state does.
func _show_swing(spec: AttackSpec, dir: Vector2, charge: float, heavy: bool) -> void:
	if spec.shape == AttackSpec.Shape.PROJECTILE or _slash_arc == null:
		return
	var reach: float = melee_reach(spec, charge, heavy)
	var seconds: float = spec.active_seconds / _attack_speed()
	var color: Color = active_weapon().color if active_weapon() != null else Color.WHITE
	_slash_arc.play(spec.shape, reach, spec.arc_degrees, dir, seconds, color)
	if not multiplayer.is_server() or _player == null:
		return
	for peer_id: int in multiplayer.get_peers():
		if peer_id != _player.peer_id:
			_remote_swing.rpc_id(peer_id, spec.shape, reach, spec.arc_degrees, dir, seconds, color)


## Host -> other clients: show this player's swing. Presentation only.
@rpc("any_peer", "call_remote", "unreliable")
func _remote_swing(shape: int, reach: float, arc_degrees: float, dir: Vector2, seconds: float, color: Color) -> void:
	if multiplayer.get_remote_sender_id() != NetworkManager.HOST_PEER_ID or _slash_arc == null:
		return
	_slash_arc.play(shape as AttackSpec.Shape, reach, arc_degrees, dir, seconds, color)


func _attack_speed() -> float:
	var stats: StatBlock = _player.stat_block as StatBlock if _player != null else null
	if stats == null:
		return 1.0
	return maxf(stats.get_value(StatBlock.Stat.ATTACK_SPEED), StatBlock.ATTACK_SPEED_MIN)


func _melee_shape(spec: AttackSpec, charge: float, heavy: bool) -> Shape2D:
	var reach: float = melee_reach(spec, charge, heavy)
	if spec.shape == AttackSpec.Shape.CIRCLE:
		var circle := CircleShape2D.new()
		circle.radius = reach
		return circle
	var half: float = deg_to_rad(spec.arc_degrees) * 0.5
	var points := PackedVector2Array([Vector2.ZERO])
	for step: int in range(ARC_SEGMENTS + 1):
		var angle: float = lerpf(-half, half, float(step) / float(ARC_SEGMENTS))
		points.append(Vector2.RIGHT.rotated(angle) * reach)
	# A fan wider than 180 degrees is not convex (the pickaxe skill is 300), so the
	# shape takes the convex hull of the points; for narrower fans that is the fan.
	var polygon := ConvexPolygonShape2D.new()
	polygon.set_point_cloud(points)
	return polygon


func _fire_projectile(spec: AttackSpec, dir: Vector2, hit: HitInfo) -> void:
	if not multiplayer.is_server():
		return
	var world: World = GameState.world
	if world == null or _player == null:
		return
	var info := ProjectileSpawnInfo.new(PROJECTILE_ID, _player.global_position + dir * 12.0, dir * spec.projectile_speed, _player.peer_id)
	var node: Node = world.projectile_spawner.spawn_projectile(info)
	var projectile: Projectile = node as Projectile
	if projectile == null:
		return
	projectile.launch(hit, Team.Kind.PLAYER, spec.projectile_range, spec.pierce)
	Events.projectile_fired.emit(_player, projectile)
