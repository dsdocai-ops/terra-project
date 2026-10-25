class_name CombatFeedback
extends Node
## Hit feedback on every peer (SPEC-combat-core "Hit feedback"): hit-stop,
## damage numbers, the sprite flash, camera shake and sparks. Owned by
## combat-core. Sync: one per peer, a child of World created by World (so the
## node path matches everywhere). Only the host sees `Events.hit_landed`. It
## applies hit-stop through TimeManager (which replicates itself), then sends
## one unreliable RPC carrying the payload below to every peer, host included
## (`call_local`), and each peer plays the presentation from that copy. Nothing
## here changes game state, so a dropped packet only costs a number.
##
## Payload: {target_path, final_damage, is_crit, is_heavy, staggered} plus
## `point` (where the spark goes) and `boss_kill` (the boss-kill shake tier),
## both derived on the host. `target_path` is relative to World.

## Emitted on this peer each time the presentation plays (tests listen).
signal feedback_played(payload: Dictionary)
## Emitted on this peer when the perfect-dodge ping shows over a player.
signal dodge_ping_played(player: Player)

const BOSS_GROUP: StringName = &"bosses"
## WeaponController tags the last step of a light combo with this.
const FINISHER_TAG: StringName = &"finisher"
const STAGGER_TEXT: String = "STAGGER"
const PERFECT_DODGE_SFX: StringName = &"perfect_dodge"

## Where numbers and sparks are parented (World/FX).
var fx_root: Node = null
## Where shake goes. Null skips shake (tests, headless).
var camera: GameCamera = null


func _ready() -> void:
	if not Events.hit_landed.is_connected(_on_hit_landed):
		Events.hit_landed.connect(_on_hit_landed)


func setup(p_fx_root: Node, p_camera: GameCamera) -> void:
	fx_root = p_fx_root
	camera = p_camera


# --- host: decide hit-stop, then replicate ----------------------------------------


## Heavy tier covers heavy attacks and light-combo finishers.
static func is_heavy_hit(hit: HitInfo) -> bool:
	return hit.is_heavy or hit.tags.has(FINISHER_TAG)


func _on_hit_landed(hit: HitInfo) -> void:
	if not multiplayer.is_server():
		return
	var target: Node2D = hit.target as Node2D
	if target == null or not is_instance_valid(target):
		return
	var boss_kill: bool = _is_boss_kill(target)
	var frames: int = CombatFeedbackConstants.hit_stop_frames(is_heavy_hit(hit), hit.is_crit, target is Player, boss_kill, hit.staggered)
	apply_hit_stop(hit, target, frames)
	var payload: Dictionary = make_payload(hit, target, boss_kill)
	if multiplayer.get_peers().is_empty():
		play_feedback(payload)
	else:
		_receive_feedback.rpc(payload)


## Freezes the target, and the attacker too unless the hit was a projectile or
## landed on a player (a player hurt freezes the player only).
func apply_hit_stop(hit: HitInfo, target: Node, frames: int) -> void:
	var other: Node = target
	var source: Node = hit.source
	if not (target is Player) and not hit.is_projectile and source != null and is_instance_valid(source) and source != target:
		other = source
	TimeManager.hit_stop(target, other, frames)


func make_payload(hit: HitInfo, target: Node2D, boss_kill: bool = false) -> Dictionary:
	var anchor: Node = get_parent() if get_parent() != null else self
	return {
		"target_path": anchor.get_path_to(target),
		"final_damage": hit.final_damage,
		"is_crit": hit.is_crit,
		"is_heavy": is_heavy_hit(hit),
		"staggered": hit.staggered,
		"point": target.global_position,
		"boss_kill": boss_kill,
	}


func _is_boss_kill(target: Node) -> bool:
	if not target.is_in_group(BOSS_GROUP):
		return false
	var health: Health = target.get_node_or_null("Health") as Health
	return health != null and health.is_dead


# --- perfect dodge -------------------------------------------------------------------


## Host: a hit was blocked by a dodge. Freezes the dodger for 3 frames and tells
## every peer to ping it.
func play_perfect_dodge(player: Player) -> void:
	if not multiplayer.is_server() or player == null or not is_instance_valid(player):
		return
	TimeManager.hit_stop(player, player, CombatFeedbackConstants.HIT_STOP_PERFECT_DODGE_FRAMES)
	var anchor: Node = get_parent() if get_parent() != null else self
	var path: NodePath = anchor.get_path_to(player)
	if multiplayer.get_peers().is_empty():
		show_dodge_ping(path)
	else:
		_receive_dodge_ping.rpc(path)


@rpc("authority", "call_local", "unreliable")
func _receive_dodge_ping(path: NodePath) -> void:
	show_dodge_ping(path)


## Every peer: the expanding ring over the dodger, and the perfect-dodge sound
## for the player who dodged.
func show_dodge_ping(path: NodePath) -> void:
	var anchor: Node = get_parent() if get_parent() != null else self
	var player: Player = anchor.get_node_or_null(path) as Player
	if player == null:
		return
	if fx_root != null:
		DodgePing.spawn(fx_root, player.global_position)
	if player.is_local:
		AudioManager.play_sfx(PERFECT_DODGE_SFX)
	dodge_ping_played.emit(player)


# --- every peer: present ------------------------------------------------------------


@rpc("authority", "call_local", "unreliable")
func _receive_feedback(payload: Dictionary) -> void:
	play_feedback(payload)


## Plays number, flash, spark and shake for one payload on this peer.
func play_feedback(payload: Dictionary) -> void:
	var anchor: Node = get_parent() if get_parent() != null else self
	var target: Node2D = anchor.get_node_or_null(payload.get("target_path", NodePath())) as Node2D
	if target == null:
		return
	var crit: bool = payload.get("is_crit", false)
	var heavy: bool = payload.get("is_heavy", false)
	var boss_kill: bool = payload.get("boss_kill", false)
	var staggered: bool = payload.get("staggered", false)
	var on_player: bool = target is Player
	if fx_root != null:
		DamageNumber.spawn(fx_root, target.global_position - Vector2(0.0, CombatFeedbackConstants.NUMBER_LIFT_PX), payload.get("final_damage", 0), crit, on_player)
		HitSpark.spawn(fx_root, payload.get("point", target.global_position), heavy or staggered)
		if staggered:
			DamageNumber.spawn_text(fx_root, target.global_position - Vector2(0.0, CombatFeedbackConstants.NUMBER_LIFT_PX * 1.8), STAGGER_TEXT)
	var flash: HitFlash = target.get_node_or_null("HitFlash") as HitFlash
	if flash != null:
		flash.flash(_flash_color(crit, on_player), CombatFeedbackConstants.FLASH_STAGGER_FRAMES if staggered else CombatFeedbackConstants.FLASH_FRAMES)
	_shake(target, heavy, crit, boss_kill, staggered)
	feedback_played.emit(payload)


static func _flash_color(crit: bool, on_player: bool) -> Color:
	if on_player:
		return HitFlash.RED
	return HitFlash.GOLD if crit else HitFlash.WHITE


## Shake is local: a hit on another player never shakes this camera.
func _shake(target: Node, heavy: bool, crit: bool, boss_kill: bool, staggered: bool = false) -> void:
	if camera == null:
		return
	var player: Player = target as Player
	if player != null and not player.is_local:
		return
	var px: float = CombatFeedbackConstants.shake_px(heavy, crit, player != null, boss_kill, staggered)
	if px > 0.0:
		camera.shake(px, CombatFeedbackConstants.SHAKE_SECONDS)
