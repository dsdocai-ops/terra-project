class_name HarnessSampleEffect
extends Effect
## The trigger harness's sample relic: a double shaped like an "on dodge"
## content item, so `tests/unit/test_effect_template.gd` can walk every harness
## affordance on a real `Effect` and a content author can see what the case they
## copy is driving. Never shipped — it lives under `tests/helpers/` beside the
## other doubles.
##
## It listens to `Events.player_dodged` through the real `Effect.listen()`
## wrapper (so the player filter and the proc rules are the production ones) and
## does the four things SPEC-effect-system's harness is specified to assert:
##
## - `spawn()`s `trail_scene` at `trail_at`,
## - adds `speed_bonus` percent to `MOVE_SPEED` through `modify()`,
## - `apply_status()`s `status_id` at `status_stacks` to `status_target`,
## - `deal_damage()`s a `hit_damage` hit to `damage_target`.
##
## Each part is off until the case sets its field, so one double covers both a
## correctly wired relic and a deliberately broken one — the template's
## "catches a broken relic" case simply leaves the fields it wants to observe
## unchanged and fires the trigger anyway.
##
## Sync: none — a test double. The real relics it stands in for are host-only
## (SPEC-effect-system, "Multiplayer ownership").

## The FX scene left behind the dodge. Null leaves no trail.
var trail_scene: PackedScene = null
## Where the trail is placed.
var trail_at: Vector2 = Vector2.ZERO
## Percent `MOVE_SPEED` the dodge grants, as a fraction (0.25 is +25%). Zero
## adds no modifier.
var speed_bonus: float = 0.0
## The status applied to `status_target`; 0 applies nothing.
var status_id: int = 0
## How many stacks of `status_id` are applied.
var status_stacks: int = 1
## The node the status lands on. Null applies no status.
var status_target: Node = null
## The node the hit is dealt to. Null deals no damage.
var damage_target: Node = null
## The hit's `base_damage`.
var hit_damage: float = 0.0


func _on_attach() -> void:
	listen(Events.player_dodged, _on_dodge)


## The relic's whole behaviour, run when its own player dodges. The dispatch
## wrapper has already filtered out a teammate's dodge and gated the proc rules.
func _on_dodge(_dodger: Player, _perfect: bool) -> void:
	if trail_scene != null:
		spawn(trail_scene, trail_at)
	if speed_bonus != 0.0:
		modify(StatBlock.Stat.MOVE_SPEED, 0.0, speed_bonus)
	if status_target != null and status_id > 0:
		apply_status(status_target, status_id, status_stacks)
	if damage_target != null and hit_damage > 0.0:
		var hit := HitInfo.new()
		hit.base_damage = hit_damage
		deal_damage(damage_target, hit)
