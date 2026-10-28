extends GutTest

## Tests for `scripts/components/interactable.gd` (W3-A5, G13b1): the component
## behind the `interact` press (SPEC-player-controller, "Interact") and the
## nearest-interactable query the press and the revive scan both run. The
## duck-typed side of the contract (Rope, Chest, ...) stands in through
## `tests/helpers/interactable_stub.gd`, which satisfies the same three members
## without extending the component.


const INTERACT_FRAMES: int = 2


class Recorder:
	## Named-method receiver for the `interacted` signal (a lambda connect
	## never fires in GUT).
	var calls: Array[Player] = []

	func record(player: Player) -> void:
		calls.append(player)


class OverrideDouble:
	extends Interactable
	## Proves `interact` is overridable: the base emit is replaced entirely.
	var used_by: Player = null

	func interact(player: Player) -> void:
		used_by = player


func _bare_player() -> Player:
	var player: Player = Player.new()
	autofree(player)
	return player


func _place(item: Area2D, at: Vector2, prompt: String = "Open",
		layer: int = Interactable.INTERACTABLE_LAYER) -> Area2D:
	item.set(&"prompt_text", prompt)
	item.collision_layer = layer
	item.collision_mask = 0
	item.position = at
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	item.add_child(shape)
	add_child_autofree(item)
	return item


func self_node() -> Node2D:
	var holder := Node2D.new()
	add_child_autofree(holder)
	return holder


# --- the component's own contract ------------------------------------------


func test_the_component_carries_the_spec_members() -> void:
	var component := Interactable.new()
	autofree(component)
	assert_eq(component.prompt_text, "", "an unnamed component offers no prompt")
	assert_eq(component.hold_seconds, 0.0, "a plain component is a press, not a hold")
	component.prompt_text = "Revive"
	component.hold_seconds = 3.0
	assert_eq(component.prompt_text, "Revive")
	assert_eq(component.hold_seconds, 3.0)


func test_the_component_sits_on_the_interactable_layer_by_itself() -> void:
	var component := Interactable.new()
	autofree(component)
	assert_eq(component.collision_layer, Interactable.INTERACTABLE_LAYER,
		"the component configures layer 6 itself, an unconfigured one is invisible to the scan")
	assert_eq(component.collision_mask, 0, "an interactable listens to nothing")


func test_interact_emits_interacted_with_the_player_once() -> void:
	var component := Interactable.new()
	component.prompt_text = "Revive"
	autofree(component)
	var recorder := Recorder.new()
	component.interacted.connect(recorder.record)
	var player := _bare_player()
	component.interact(player)
	assert_eq(recorder.calls.size(), 1, "one press, one emit")
	assert_eq(recorder.calls[0], player, "the emit carries the player that pressed")


func test_an_override_replaces_the_base_emit() -> void:
	var overrider := OverrideDouble.new()
	overrider.prompt_text = "Revive"
	autofree(overrider)
	var recorder := Recorder.new()
	overrider.interacted.connect(recorder.record)
	var player := _bare_player()
	overrider.interact(player)
	assert_eq(overrider.used_by, player, "the override received the press")
	assert_true(recorder.calls.is_empty(), "the override replaced the base emit")


# --- is_usable, duck-typed over every interactable --------------------------


func test_is_usable_accepts_the_component_and_the_stub_alike() -> void:
	var component := Interactable.new()
	component.prompt_text = "Open"
	autofree(component)
	var stub: Area2D = InteractableStub.new()
	autofree(stub)
	assert_false(stub is Interactable, "the stub does not extend the component")
	assert_true(Interactable.is_usable(component), "a prompted component is usable")
	assert_true(Interactable.is_usable(stub),
		"the scan duck-types: the stub satisfies the contract without extending it")


func test_is_usable_refuses_no_prompt_no_interact_and_null() -> void:
	var bare := Interactable.new()
	autofree(bare)
	assert_false(Interactable.is_usable(bare), "an empty prompt is not usable")
	assert_false(Interactable.is_usable(autofree(Node2D.new())),
		"a node without interact() is not usable")
	assert_false(Interactable.is_usable(null))


# --- the nearest query -------------------------------------------------------


func test_nearest_finds_a_usable_stub_in_reach_and_prefers_the_closest() -> void:
	var near := _place(InteractableStub.new(), Vector2(10, 0))
	_place(InteractableStub.new(), Vector2(30, 0))
	await wait_physics_frames(INTERACT_FRAMES)
	assert_eq(Interactable.nearest(self_node(), Vector2.ZERO), near)


func test_nearest_keeps_a_centre_exactly_on_the_radius_edge() -> void:
	var on_edge := _place(InteractableStub.new(), Vector2(40, 0))
	await wait_physics_frames(INTERACT_FRAMES)
	assert_eq(Interactable.nearest(self_node(), Vector2.ZERO), on_edge,
		"the spec's \"within 40 px\" includes the 40 px centre")


func test_nearest_drops_a_centre_just_outside_the_radius() -> void:
	_place(InteractableStub.new(), Vector2(40.1, 0))
	await wait_physics_frames(INTERACT_FRAMES)
	assert_null(Interactable.nearest(self_node(), Vector2.ZERO),
		"its shape still overlaps the query circle; the centre distance rejects it")


func test_nearest_ignores_far_ones_empty_prompts_and_other_layers() -> void:
	_place(InteractableStub.new(), Vector2(300, 0))
	_place(InteractableStub.new(), Vector2(5, 0), "")
	_place(InteractableStub.new(), Vector2(5, 5), "Open", 1)
	await wait_physics_frames(INTERACT_FRAMES)
	assert_null(Interactable.nearest(self_node(), Vector2.ZERO))


func test_nearest_takes_the_caller_radius_so_the_revive_scan_can_reach_48() -> void:
	var stub := _place(InteractableStub.new(), Vector2(45, 0))
	await wait_physics_frames(INTERACT_FRAMES)
	assert_null(Interactable.nearest(self_node(), Vector2.ZERO),
		"the default 40 px press radius does not reach it")
	assert_eq(Interactable.nearest(self_node(), Vector2.ZERO, 48.0), stub,
		"the revive scan's 48 px (SPEC-player-controller, Downed and revive) does")


func test_nearest_finds_the_real_component_and_wins_over_a_farther_stub() -> void:
	var component := Interactable.new()
	var placed := _place(component, Vector2(12, 0), "Revive")
	_place(InteractableStub.new(), Vector2(30, 0))
	await wait_physics_frames(INTERACT_FRAMES)
	assert_eq(placed, component, "the helper placed the component itself")
	assert_eq(Interactable.nearest(self_node(), Vector2.ZERO), component)


func test_nearest_returns_null_when_nothing_is_in_reach() -> void:
	await wait_physics_frames(INTERACT_FRAMES)
	assert_null(Interactable.nearest(self_node(), Vector2.ZERO))
