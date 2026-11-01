class_name AbilityCast
extends Node2D
## The node one cast of an ability runs as: the root of every ability's cast
## scene. Owned by abilities. Sync: host only. The host spawns it, runs `_perform`
## and builds the hits; a client's copy (made by AbilityController from the host's
## broadcast) only shows the cast, because Hurtbox.receive early-returns on
## clients. Its life runs in TimeManager-scaled time of the owning player, and it
## frees itself when the life ends.
##
## Call setup() before add_child(): `_ready` runs `_perform` on the host, and
## `_perform` reads the player, data and rank that setup() sets.

## Tag every ability hit carries, next to the ability's own id.
const ABILITY_TAG: StringName = &"ability"
## The status an element's hit applies (Fire burns, Frost chills, Storm shocks).
## An element missing here applies no status. Read by build_hit as a
## StatusApplication, so the status path is the existing one.
const ELEMENT_STATUS: Dictionary[int, int] = {
	HitInfo.Element.FIRE: StatusEffects.Status.BURN,
	HitInfo.Element.FROST: StatusEffects.Status.CHILL,
	HitInfo.Element.STORM: StatusEffects.Status.SHOCK,
	HitInfo.Element.POISON: StatusEffects.Status.TOXIN,
	HitInfo.Element.SHADOW: StatusEffects.Status.MARK,
	HitInfo.Element.BLOOD: StatusEffects.Status.BLEED,
	HitInfo.Element.VOID: StatusEffects.Status.UNRAVEL,
}

var player: Player = null
var data: AbilityData = null
var rank: int = 1
## Where the cursor was when the cast was made, and the normalized aim from the
## player toward it (RIGHT when the two are at the same point).
var aim_point: Vector2 = Vector2.ZERO
var aim_dir: Vector2 = Vector2.RIGHT
## Seconds of TimeManager-scaled life, from the rank's duration.
var life_seconds: float = 0.0

var _life_left: float = 0.0


## Sets what the cast needs before it enters the tree.
func setup(player_node: Player, ability: AbilityData, ability_rank: int, aim: Vector2, dir: Vector2) -> void:
	player = player_node
	data = ability
	rank = ability_rank
	aim_point = aim
	aim_dir = dir.normalized() if not dir.is_zero_approx() else Vector2.RIGHT
	var rank_data: AbilityRank = ability.rank_data(ability_rank) if ability != null else null
	life_seconds = rank_data.duration if rank_data != null else 0.0
	_life_left = life_seconds


func _ready() -> void:
	if multiplayer.is_server():
		_perform()


func _physics_process(delta: float) -> void:
	advance(delta)


## Runs the cast's life for `delta` seconds of TimeManager-scaled time and frees
## the cast when it ends. Public so tests can run it without physics frames.
func advance(delta: float) -> void:
	_life_left -= delta * TimeManager.scale_for(_timed_node())
	if _life_left <= 0.0:
		queue_free()


## The hit template for one hit of this cast: the ability's base damage at this
## rank, its element, and the tags that name the ability. Host only, since the
## hit is built for Hurtbox.receive.
func build_hit() -> HitInfo:
	var hit := HitInfo.new()
	hit.source = player
	hit.owner_player = player
	hit.base_damage = _base_damage_at_rank()
	hit.element = data.element if data != null else HitInfo.Element.NONE
	hit.scales_with_ability_power = true
	hit.tags = [ABILITY_TAG]
	if data != null:
		hit.tags.append(data.id)
	var status: int = ELEMENT_STATUS.get(hit.element, -1)
	if status >= 0:
		hit.statuses.append(StatusApplication.make(status, 1))
	return hit


## A copy of the hit template with its base damage scaled by `factor`, for the
## parts of a cast that hit softer (a burning ground, a trailing wall).
func scaled_hit(factor: float) -> HitInfo:
	var hit := build_hit()
	hit.base_damage *= factor
	return hit


## What the cast does on the host when it spawns. Cast scenes override it.
func _perform() -> void:
	pass


## Spawns one Zone under this cast at `point`: `radius` pixels across, alive for
## `seconds`, ticking a copy of `template` every `interval`. Host only. Returns
## the zone, which is the cast's child, so it frees with the cast.
func spawn_zone(point: Vector2, radius: float, seconds: float, interval: float, template: HitInfo) -> Zone:
	var zone := Zone.new()
	zone.set_radius(radius)
	zone.configure(template, seconds, interval, player)
	add_child(zone)
	zone.global_position = point
	return zone


## Where the cast starts: the player's position, or this cast's own position when
## it has no player.
func origin() -> Vector2:
	if player != null and player.is_inside_tree():
		return player.global_position
	return global_position


## The rank's size multiplier, 1.0 with no rank data.
func size_mult() -> float:
	var rank_data: AbilityRank = data.rank_data(rank) if data != null else null
	return rank_data.size_mult if rank_data != null else 1.0


## The rank's `extra` number (the ability's own value, such as a jump count),
## 0.0 with no rank data.
func extra() -> float:
	var rank_data: AbilityRank = data.rank_data(rank) if data != null else null
	return rank_data.extra if rank_data != null else 0.0


func _base_damage_at_rank() -> float:
	if data == null:
		return 0.0
	var rank_data: AbilityRank = data.rank_data(rank)
	var mult: float = rank_data.damage_mult if rank_data != null else 1.0
	return data.base_damage * mult


## The node whose TimeManager scale runs this cast: the player, or this node when
## the cast has no player.
func _timed_node() -> Node:
	if player != null:
		return player
	return self
