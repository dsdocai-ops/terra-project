class_name Interactable
extends Area2D
## The component behind the `interact` press (SPEC-player-controller, "Interact"):
## the nearest `Interactable` within 40 px is offered, and the press calls its
## `interact(player)`. Owned by player-controller. An interactable is any area
## on physics layer 6 with `prompt_text` and `interact(player)` — Rope, Chest,
## Shrine and the town buildings predate this component and satisfy the same
## three members duck-typed, so the scan and `is_usable` accept any of them;
## new interactables attach or extend this one instead of re-declaring them.
## Sync: none. The scan is local presentation; `interact` does whatever the
## concrete interactable's own code does (several forward to the host on a
## client), so this component carries no replicated state.

## Emitted by the base `interact`, so an attached component (no subclass) can
## be wired with a connection; an override replaces the emit entirely.
signal interacted(player: Player)

## Physics layer 6, "interactable" (project.godot layer_names).
const INTERACTABLE_LAYER: int = 32

## World pixels from the player within which the press finds one
## (SPEC-player-controller: "nearest `Interactable` ... within 40 px"; the
## revive hold's own 48 px is passed as the radius by its caller).
const INTERACT_RADIUS: float = 40.0

## What the prompt shows ("[F] " + this).
@export var prompt_text: String = ""

## Seconds the `interact` action must be held. 0.0 is a plain press; the revive
## is the only hold in week 3 (SPEC-player-controller: "Hold handled for revive
## only"), and its caller scales the value it sets by `revive_speed_mult`.
@export var hold_seconds: float = 0.0


func _init() -> void:
	# An interactable the scan cannot see is a dead one, so the layer comes with
	# the component (the scene-built ones set it in their own scripts today).
	collision_layer = INTERACTABLE_LAYER
	collision_mask = 0


func interact(player: Player) -> void:
	interacted.emit(player)


## True for an area that can be used: it has a prompt and an `interact` method.
## Duck-typed on purpose — every existing interactable satisfies the contract
## without extending this class.
static func is_usable(item: Object) -> bool:
	return item != null and item.has_method(&"interact") and &"prompt_text" in item \
			and not String(item.get(&"prompt_text")).is_empty()


## The closest usable interactable whose centre is within `radius` of `point`,
## or null. Scans physics layer 6 for areas only.
static func nearest(from: Node2D, point: Vector2, radius: float = INTERACT_RADIUS) -> Node2D:
	var query := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	query.shape = circle
	query.transform = Transform2D(0.0, point)
	query.collision_mask = INTERACTABLE_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var best: Node2D = null
	var best_distance: float = INF
	for hit: Dictionary in from.get_world_2d().direct_space_state.intersect_shape(query, 16):
		var item := hit.get("collider") as Node2D
		if not is_usable(item):
			continue
		# The shape query catches overlaps; the centre distance is the contract,
		# so a big shape poking into reach cannot offer a far-away centre.
		var distance: float = item.global_position.distance_to(point)
		if distance > radius:
			continue
		if distance < best_distance:
			best_distance = distance
			best = item
	return best
