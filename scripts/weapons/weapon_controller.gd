class_name WeaponController
extends Node
## Holds a player's two weapon slots and turns an `AttackSpec` into a live hit:
## a melee hitbox in front of the player or a projectile (SPEC-weapons
## `WeaponController`). Owned by weapons. Sync: host-authoritative. Hitboxes and
## projectile spawns run on the host only (`Hurtbox.receive` and the spawner
## both refuse clients); a client runs the same calls so its movement and
## timing predict the host's, and nothing it spawns can deal damage.

signal weapon_changed(slot: int, weapon: WeaponData)
## A swing went live, with the spec it played and the hit it carries. Local to this
## controller, so Shadow Clones can copy the owner's melee swings. Emitted on every
## peer; only the host's hits land.
signal swing_begun(spec: AttackSpec, hit: HitInfo)
## Whether the active slot's weapon is on the class affinity list (SPEC-weapons
## "Class affinity hooks"). Emitted when the active slot is equipped (an empty slot
## is false), when the active slot changes, and when the class sets its list. Every
## peer runs the same calls; the class effect that attaches on it is host-side.
signal affinity_active_changed(active: bool)

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
## Each Blacksmith damage tier adds this share to ATTACK (SPEC-town "weapon damage
## tier +10%"). Applied as a StatBlock modifier under TIER_SOURCE, never a base edit.
const TIER_PERCENT_PER_TIER: float = 0.10
const TIER_SOURCE: StringName = &"blacksmith_tier"
## A heavy's reach grows with its charge in this many steps (0 to 4 quarters), so
## the hitbox shapes can be cached per attack and bucket instead of built per
## swing. The slash arc uses the same stepped reach, so it shows the real hitbox.
const CHARGE_BUCKETS: int = 4
const DEFAULT_WEAPON_PATHS: Array[String] = [
	"res://data/weapons/pickaxe.tres",
	"res://data/weapons/crossbow.tres",
]
const PROJECTILE_ID: StringName = &"bolt"
## Where the per-weapon attack node scenes live (SPEC-weapons data model,
## `scenes/player/weapons/<id>.tscn`). A weapon without a scene there runs the
## no-op base hooks.
const ATTACK_SCENE_DIR: String = "res://scenes/player/weapons/"

var slots: Array[WeaponData] = []
var active_slot: int = 0
var combo_step: int = 0
## The 0-based light combo step now playing: `take_light` records it before the
## swing runs and the attack hook passes it through.
var last_light_step: int = 0

## One attack node (SPEC-weapons `WeaponAttack`) per weapon id, made on first
## use and kept for the run; the active weapon's entry is what `begin_swing`
## routes through.
var _attack_nodes: Dictionary = {}

## Cracks this controller forwarded to other peers (one per target peer); the
## two-instance smoke reads it on the host. Smoke evidence, not state.
var cracks_forwarded: int = 0
## Cracks received over the host's RPC on this controller; the two-instance
## smoke reads it on the client. Smoke evidence, not state.
var remote_cracks_received: int = 0

## One hitbox shape per AttackSpec and charge bucket, built the first time it is
## swung and reused after that: swinging allocates no shapes once warm. (Per
## controller, not a static: a static cache of Resources trips the engine's leak
## report at shutdown.) AttackSpecs are immutable at run time, so entries never
## go stale.
var _shape_cache: Dictionary = {}

var _combo_timer: float = 0.0
## Seconds left on each slot's weapon skill, counted in TimeManager-scaled time.
var _skill_cooldowns: Array[float] = [0.0, 0.0]
## Blacksmith damage tier per slot (SPEC-weapons). Only the active slot's tier is
## applied to the player's ATTACK, through `_apply_damage_tier`.
var _slot_tiers: Array[int] = [0, 0]
var _swap_lockout: float = 0.0
var _hitbox: Hitbox = null
var _hitbox_shape: CollisionShape2D = null
var _slash_arc: SlashArc = null
var _player: Player = null
## The weapon ids the class counts as its affinity (ClassData.affinity_weapon_ids),
## set by `set_affinity_ids`. Empty until a class is chosen.
var _affinity_ids: Array[StringName] = []


func _ready() -> void:
	_player = get_parent() as Player
	slots.resize(SLOT_COUNT)
	for index: int in SLOT_COUNT:
		var data := load(DEFAULT_WEAPON_PATHS[index]) as WeaponData
		slots[index] = data
		_slot_tiers[index] = _profile_tier(data)
	_apply_damage_tier()
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


## Equips `data` into `slot` with its Blacksmith damage tier (0 for none). The
## tier only reaches ATTACK while its slot is the active one (`_apply_damage_tier`).
func equip(slot: int, data: WeaponData, damage_tier: int = 0) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	slots[slot] = data
	_slot_tiers[slot] = maxi(damage_tier, 0)
	combo_step = 0
	if slot == active_slot:
		_apply_damage_tier()
	weapon_changed.emit(slot, data)
	if slot == active_slot:
		_announce_affinity()


func active_weapon() -> WeaponData:
	return slots[active_slot]


## Sets the weapon ids the class counts as its affinity, and announces the active
## weapon's state so an attached class effect can re-sync.
func set_affinity_ids(ids: Array[StringName]) -> void:
	_affinity_ids = ids.duplicate()
	_announce_affinity()


func _is_affinity(data: WeaponData) -> bool:
	return data != null and _affinity_ids.has(data.id)


func _announce_affinity() -> void:
	affinity_active_changed.emit(_is_affinity(active_weapon()))


func can_swap() -> bool:
	return _swap_lockout <= 0.0


## Swaps to the other slot unless the 0.2 s lockout is running. Returns whether
## it swapped.
func swap() -> bool:
	return select_slot((active_slot + 1) % SLOT_COUNT)


## Equips a slot directly (the `weapon_1` / `weapon_2` inputs): the same 0.2 s
## lockout as a swap, and a no-op when that slot is already live. Selecting the
## live slot neither moves nor restarts the lockout.
func select_slot(index: int) -> bool:
	if index < 0 or index >= SLOT_COUNT or not can_swap() or index == active_slot:
		return false
	active_slot = index
	_swap_lockout = SWAP_LOCKOUT_SECONDS
	combo_step = 0
	_apply_damage_tier()
	weapon_changed.emit(active_slot, slots[active_slot])
	_announce_affinity()
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
	var step: int = combo_step % weapon.light_combo.size()
	last_light_step = step
	var spec: AttackSpec = weapon.light_combo[step]
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
	if _is_affinity(weapon):
		hit.tags.append(&"affinity")
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
	swing_begun.emit(spec, hit)
	_run_attack_hook(spec, dir, charge, heavy)
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


## Routes the swing to the active weapon's attack node (SPEC-weapons
## `WeaponAttack`): the skill hook for a weapon skill, `heavy(charge)` for a
## heavy, `light(step)` for a light combo step. The generic hitbox above is
## untouched.
func _run_attack_hook(spec: AttackSpec, dir: Vector2, charge: float, heavy: bool) -> void:
	var weapon: WeaponData = active_weapon()
	var node: WeaponAttack = _attack_node_for(weapon)
	if node == null:
		return
	node.aim_dir = dir
	if weapon != null and weapon.skill == spec:
		node.skill()
	elif heavy:
		node.heavy(charge)
	else:
		node.light(last_light_step)


## The attack node for `weapon`, made on first use and kept for the run:
## instanced from the weapon's scene in `ATTACK_SCENE_DIR`, or the no-op base
## while a weapon has no scene yet.
func _attack_node_for(weapon: WeaponData) -> WeaponAttack:
	if weapon == null:
		return null
	if _attack_nodes.has(weapon.id):
		return _attack_nodes[weapon.id] as WeaponAttack
	var node: WeaponAttack = _make_attack_node(weapon)
	_attack_nodes[weapon.id] = node
	return node


func _make_attack_node(weapon: WeaponData) -> WeaponAttack:
	var node: WeaponAttack = null
	var path := ATTACK_SCENE_DIR + String(weapon.id) + ".tscn"
	if ResourceLoader.exists(path):
		node = (load(path) as PackedScene).instantiate() as WeaponAttack
	if node == null:
		node = WeaponAttack.new()
	node.name = "WeaponAttack_" + String(weapon.id)
	node.weapons = self
	node.player = _player
	add_child(node)
	return node


## Forward reach of a melee swing in px, including the heavy's charge bonus.
static func melee_reach(spec: AttackSpec, charge: float, heavy: bool) -> float:
	var stepped: float = float(charge_bucket(charge, heavy)) / float(CHARGE_BUCKETS)
	return spec.reach * (1.0 + stepped * 0.35)


## Which quarter of the charge a swing falls in: 0 for a light or an uncharged heavy.
static func charge_bucket(charge: float, heavy: bool) -> int:
	if not heavy:
		return 0
	return clampi(roundi(charge * float(CHARGE_BUCKETS)), 0, CHARGE_BUCKETS)


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


## Re-writes the active slot's Blacksmith tier as the one ATTACK modifier this
## controller owns. Runs on every peer (no server check), but only the host's
## ATTACK feeds damage (`Damage.compute` runs on the host). A tier of 0 adds nothing.
func _apply_damage_tier() -> void:
	# The StatBlock child by name: `_ready` runs before the player's @onready
	# `stat_block` is set, and the tier must still land on the first frame.
	var stats := _player.get_node_or_null("StatBlock") as StatBlock if _player != null else null
	if stats == null:
		return
	stats.remove_source(TIER_SOURCE)
	var tier: int = _slot_tiers[active_slot]
	if tier > 0:
		stats.add_modifier(StatBlock.Stat.ATTACK, 0.0, tier * TIER_PERCENT_PER_TIER, TIER_SOURCE)


## The Blacksmith tier the local profile holds for `data` (0 when none). Only
## this machine's own player reads its profile: on the host, a remote client's
## player is spawned with the host's profile, which holds the host's tiers, so
## the tier is 0 there. The weapon id is the data file's name (`pickaxe.tres` is
## `pickaxe`), the key `PlayerProfile.weapon_damage_tiers` uses. Owned by weapons;
## sync: none, the profile is a local file. Carrying a remote player's tier to the
## host is not built yet (W4-A5 finding in .goals/LOG.md).
func _profile_tier(data: WeaponData) -> int:
	var profile: PlayerProfile = SaveManager.profile
	if profile == null or data == null or _player == null:
		return 0
	if _player.peer_id != multiplayer.get_unique_id():
		return 0
	var weapon_id: String = data.resource_path.get_file().get_basename()
	return int(profile.weapon_damage_tiers.get(weapon_id, 0))


func _attack_speed() -> float:
	var stats: StatBlock = _player.stat_block as StatBlock if _player != null else null
	if stats == null:
		return 1.0
	return maxf(stats.get_value(StatBlock.Stat.ATTACK_SPEED), StatBlock.ATTACK_SPEED_MIN)


## The hitbox shape for a swing: cached per spec and charge bucket.
func _melee_shape(spec: AttackSpec, charge: float, heavy: bool) -> Shape2D:
	var bucket: int = charge_bucket(charge, heavy)
	var shapes: Array = _shape_cache.get(spec, [])
	if shapes.is_empty():
		shapes.resize(CHARGE_BUCKETS + 1)
		_shape_cache[spec] = shapes
	var cached: Shape2D = shapes[bucket] as Shape2D
	if cached == null:
		cached = _build_melee_shape(spec, melee_reach(spec, charge, heavy))
		shapes[bucket] = cached
	return cached


func _build_melee_shape(spec: AttackSpec, reach: float) -> Shape2D:
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


## The spawn data for one shot, read at the moment the swing goes live: the
## attack hook's size for this swing rides along, so every peer draws the bolt
## that does the hitting (the crossbow's charged bolt), not a base-size copy.
func build_spawn_info(spec: AttackSpec, dir: Vector2) -> ProjectileSpawnInfo:
	var attack_node: WeaponAttack = _attack_node_for(active_weapon())
	var shot_scale: float = attack_node.shot_scale if attack_node != null else 1.0
	return ProjectileSpawnInfo.new(
		PROJECTILE_ID,
		_player.global_position + dir * 12.0,
		dir * spec.projectile_speed,
		_player.peer_id,
		Vector2.ONE * shot_scale,
	)


func _fire_projectile(spec: AttackSpec, dir: Vector2, hit: HitInfo) -> void:
	if not multiplayer.is_server():
		return
	var world: World = GameState.world
	if world == null or _player == null:
		return
	var node: Node = world.projectile_spawner.spawn_projectile(build_spawn_info(spec, dir))
	var projectile: Projectile = node as Projectile
	if projectile == null:
		return
	projectile.launch(hit, Team.Kind.PLAYER, spec.projectile_range, spec.pierce)
	Events.projectile_fired.emit(_player, projectile)


## A weapon hook just struck a ground crack (the pickaxe heavy): spawn it
## locally and — on the host — forward it to every peer that does not run this
## swing itself, so the signature is visible on remote peers too. Presentation
## only, the same channel the slash arc rides.
func strike_ground_crack(origin: Vector2, dir: Vector2, length_px: float) -> void:
	_spawn_local_crack(origin, dir, length_px)
	broadcast_ground_crack(origin, dir, length_px)


## Peers that did not run this swing: everyone connected except the owner, who
## drew its own crack inside the hook. Static so tests pin the exclusion
## without a live multiplayer peer.
static func crack_targets(owner_peer_id: int, connected: Array[int]) -> Array[int]:
	var targets: Array[int] = []
	for peer_id: int in connected:
		if peer_id != owner_peer_id:
			targets.append(peer_id)
	return targets


## Host -> other peers (never the owner, who drew its own inside the hook).
func broadcast_ground_crack(origin: Vector2, dir: Vector2, length_px: float) -> void:
	if not multiplayer.is_server() or _player == null:
		return
	var connected: Array[int] = []
	for peer_id: int in multiplayer.get_peers():
		connected.append(peer_id)
	for peer_id: int in crack_targets(_player.peer_id, connected):
		_remote_ground_crack.rpc_id(peer_id, origin, dir.normalized(), length_px)
		cracks_forwarded += 1


## Presentation of a swing this peer did not run. Unreliable like the slash arc:
## a dropped crack is a 0.7 s decal, not state.
@rpc("any_peer", "call_remote", "unreliable")
func _remote_ground_crack(origin: Vector2, dir: Vector2, length_px: float) -> void:
	if multiplayer.get_remote_sender_id() != NetworkManager.HOST_PEER_ID or _player == null:
		return
	remote_cracks_received += 1
	_spawn_local_crack(origin, dir, length_px)


## The local half both a swing this peer ran and a crack received over the RPC
## share: the same decal, struck at the same inputs.
func _spawn_local_crack(origin: Vector2, dir: Vector2, length_px: float) -> void:
	GroundCrackLine.spawn(_fx_parent(), origin, dir, length_px)


## Where swing FX live: the world's FX layer, or the player's parent when no
## world exists (tests, scene-less setups) so the node is always in the tree.
func _fx_parent() -> Node:
	var world: World = GameState.world
	if world != null and is_instance_valid(world) and world.fx != null:
		return world.fx
	return _player.get_parent() if _player != null else self
